import Foundation

@MainActor
final class ConnectionManager: ObservableObject {
    private let transport: VoiceTransport
    private let surface: Surface
    private var audioCapture: AudioCapturing
    private var audioPlayback: AudioPlaying
    private let sessionID = UUID().uuidString
    private let sessionAuthToken: String?
    private var responseTimeoutTask: Task<Void, Never>?
    private var isInterruptingResponse = false
    private var suppressedTurnIDs: Set<String> = []
    private let thinkingAckTimeoutSeconds: UInt64 = 12
    private let responseAfterThinkingTimeoutSeconds: UInt64 = 90

    init(
        surface: Surface = .iphone,
        transport: VoiceTransport = WebSocketVoiceClient(),
        sessionAuthToken: String? = nil,
        audioCapture: AudioCapturing? = nil,
        audioPlayback: AudioPlaying? = nil
    ) {
        self.surface = surface
        self.transport = transport
        let normalized = sessionAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.sessionAuthToken = normalized.isEmpty ? nil : normalized
        self.audioCapture = audioCapture ?? AppleSpeechAudioCaptureService()
        self.audioPlayback = audioPlayback ?? AVSpeechAudioPlaybackService()
    }

    private func bindPlaybackCallbacks(to appState: AppState) {
        audioPlayback.onPlaybackStateChanged = { [weak appState] isActive in
            guard let appState else { return }
            appState.setPlaybackActive(isActive)

            if isActive {
                if appState.clientState == .thinking || appState.clientState == .idle {
                    appState.apply(.receivedChunk)
                }
            } else if appState.clientState == .speaking {
                appState.apply(.speechPlaybackFinished)
            }
        }
    }

    func connectIfNeeded(appState: AppState) async {
        guard appState.connectionStatus == .disconnected else { return }

        bindPlaybackCallbacks(to: appState)
        appState.connectionStatus = .connecting
        appState.setSurface(surface)

        transport.onServerEvent = { [weak self, weak appState] result in
            Task { @MainActor [weak self, weak appState] in
                guard let self, let appState else { return }
                switch result {
                case .success(let event):
                    self.map(event, to: appState)
                case .failure(let error):
                    appState.connectionStatus = .disconnected
                    appState.setError("Connection error: \(error.localizedDescription)")
                }
            }
        }

        do {
            try await transport.connect()
            appState.connectionStatus = .connected

            try await transport.send(
                event: ClientEventEnvelope(
                    sessionID: sessionID,
                    surface: surface,
                    type: .sessionStart,
                    payload: SessionStartPayload(
                        clientVersion: "0.1.0",
                        deviceID: nil,
                        authToken: sessionAuthToken
                    )
                )
            )
        } catch {
            cancelResponseTimeout()
            appState.connectionStatus = .disconnected
            appState.setError("Failed to connect: \(error.localizedDescription)")
        }
    }

    func startPushToTalk(appState: AppState) async {
        cancelResponseTimeout()
        bindPlaybackCallbacks(to: appState)
        guard await ensureConnected(appState: appState) else {
            appState.setError("Not connected to backend. Start backend and reconnect.")
            return
        }

        audioCapture.onPartialTranscript = { [weak self, weak appState] partial in
            Task { @MainActor [weak self, weak appState] in
                guard let self, let appState else { return }
                let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                appState.liveTranscript = trimmed
                Task { [weak self] in
                    guard let self else { return }
                    try? await self.transport.send(
                        event: ClientEventEnvelope(
                            sessionID: self.sessionID,
                            surface: self.surface,
                            type: .transcriptPartial,
                            payload: TranscriptPayload(text: trimmed)
                        )
                    )
                }
            }
        }

        do {
            try await audioCapture.startCapture()
            appState.apply(.startListening)
        } catch {
            appState.setError("Failed to start audio capture: \(error.localizedDescription)")
        }
    }

    func interruptAndStartPushToTalk(appState: AppState) async {
        cancelResponseTimeout()
        isInterruptingResponse = true

        audioCapture.onPartialTranscript = nil
        audioCapture.cancelCapture()
        audioPlayback.stopSession()
        appState.setPlaybackActive(false)
        appState.clearStreamingAssistantText()
        appState.setPendingAction(nil)
        appState.apply(.cancel)

        await startPushToTalk(appState: appState)
    }

    func stopPushToTalk(appState: AppState, transcript: String) async {
        let captureResult: CapturedAudioResult
        do {
            captureResult = try await audioCapture.stopCapture()
            audioCapture.onPartialTranscript = nil
        } catch {
            audioCapture.onPartialTranscript = nil
            appState.setError("Failed to stop audio capture: \(error.localizedDescription)")
            return
        }

        let sourceText = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (captureResult.transcriptCandidate ?? "")
            : transcript
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appState.setError("Transcript cannot be empty")
            return
        }

        appState.apply(.stopListening)
        appState.liveTranscript = trimmed
        appState.transcriptHistory.append(trimmed)
        audioPlayback.startSession()
        isInterruptingResponse = false

        guard await ensureConnected(appState: appState) else {
            appState.setError("Connection lost before sending transcript.")
            return
        }

        do {
            try await transport.send(
                event: ClientEventEnvelope(
                    sessionID: sessionID,
                    surface: surface,
                    type: .transcriptFinal,
                    payload: TranscriptPayload(text: trimmed)
                )
            )
            appState.apply(.transcriptSent)
            scheduleThinkingTimeout(appState: appState)
        } catch {
            appState.setError("Failed to send transcript: \(error.localizedDescription)")
        }
    }

    func cancel(appState: AppState) async {
        cancelResponseTimeout()
        audioCapture.onPartialTranscript = nil
        audioCapture.cancelCapture()
        do {
            try await transport.send(
                event: ClientEventEnvelope(
                    sessionID: sessionID,
                    surface: surface,
                    type: .sessionEnd,
                    payload: SessionEndPayload(reason: "user_cancelled")
                )
            )
            await transport.disconnect()
            audioPlayback.stopSession()
            appState.setPlaybackActive(false)
            appState.connectionStatus = .disconnected
            appState.setPendingAction(nil)
            appState.apply(.cancel)
        } catch {
            await transport.disconnect()
            appState.setPlaybackActive(false)
            appState.connectionStatus = .disconnected
            appState.setError("Failed to cancel session: \(error.localizedDescription)")
        }
    }

    func confirmPendingAction(appState: AppState) async {
        guard appState.pendingAction != nil else { return }

        appState.setPendingAction(nil)
        appState.apply(.actionConfirmed)

        // TODO: send action confirmation event when protocol adds it.
        map(
            .assistantResponseChunk(
                ServerEventEnvelope(
                    version: "1.0",
                    eventID: UUID().uuidString,
                    timestamp: Date(),
                    sessionID: sessionID,
                    surface: surface,
                    type: .assistantResponseChunk,
                    payload: AssistantResponseChunkPayload(
                        turnID: UUID().uuidString,
                        text: "(placeholder) Action confirmed. Continuing..."
                    )
                )
            ),
            to: appState
        )
        map(
            .assistantResponseFinal(
                ServerEventEnvelope(
                    version: "1.0",
                    eventID: UUID().uuidString,
                    timestamp: Date(),
                    sessionID: sessionID,
                    surface: surface,
                    type: .assistantResponseFinal,
                    payload: AssistantResponseFinalPayload(
                        turnID: UUID().uuidString,
                        text: "(placeholder) Done."
                    )
                )
            ),
            to: appState
        )
    }

    private func map(_ event: ServerEvent, to appState: AppState) {
        switch event {
        case .assistantThinking:
            if isInterruptingResponse { return }
            appState.apply(.receivedThinking)
            scheduleResponseTimeout(appState: appState)
        case .assistantResponseChunk(let envelope):
            if isInterruptingResponse {
                suppressedTurnIDs.insert(envelope.payload.turnID)
                return
            }
            if suppressedTurnIDs.contains(envelope.payload.turnID) {
                return
            }
            cancelResponseTimeout()
            appState.apply(.receivedChunk)
            appState.streamingAssistantText += envelope.payload.text + "\n"
            audioPlayback.startSession()
            audioPlayback.playTextChunk(envelope.payload.text, isFinal: false)
        case .assistantResponseFinal(let envelope):
            if isInterruptingResponse {
                suppressedTurnIDs.insert(envelope.payload.turnID)
                return
            }
            if suppressedTurnIDs.contains(envelope.payload.turnID) {
                suppressedTurnIDs.remove(envelope.payload.turnID)
                return
            }
            cancelResponseTimeout()
            appState.assistantHistory.append(envelope.payload.text)
            audioPlayback.startSession()
            audioPlayback.playTextChunk(envelope.payload.text, isFinal: true)
            appState.clearStreamingAssistantText()
            appState.apply(.receivedFinalResponse)
        case .actionProposed(let envelope):
            let action = PendingAction(
                id: envelope.payload.actionID,
                title: envelope.payload.title,
                summary: envelope.payload.summary,
                reason: "Awaiting explicit confirmation"
            )
            appState.setPendingAction(action)
        case .actionConfirmationRequired(let envelope):
            if let current = appState.pendingAction {
                appState.setPendingAction(
                    PendingAction(
                        id: current.id,
                        title: current.title,
                        summary: current.summary,
                        reason: envelope.payload.reason
                    )
                )
            }
            appState.apply(.confirmationRequired)
        case .sessionEnd:
            cancelResponseTimeout()
            appState.connectionStatus = .disconnected
            audioPlayback.stopSession()
            appState.setPlaybackActive(false)
            isInterruptingResponse = false
            suppressedTurnIDs.removeAll()
            appState.apply(.sessionEnded)
        case .error(let envelope):
            cancelResponseTimeout()
            if envelope.payload.code == "auth_failed" {
                appState.connectionStatus = .disconnected
                Task { [transport] in
                    await transport.disconnect()
                }
            }
            appState.setPlaybackActive(false)
            isInterruptingResponse = false
            suppressedTurnIDs.removeAll()
            appState.setError(envelope.payload.message)
        }
    }

    private func scheduleThinkingTimeout(appState: AppState) {
        cancelResponseTimeout()
        responseTimeoutTask = Task { [weak appState] in
            try? await Task.sleep(nanoseconds: thinkingAckTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled, let appState else { return }
            if appState.clientState == .transcribing || appState.clientState == .thinking {
                appState.setError("Backend is taking too long to acknowledge your request. Please try again.")
            }
        }
    }

    private func scheduleResponseTimeout(appState: AppState) {
        cancelResponseTimeout()
        responseTimeoutTask = Task { [weak appState] in
            try? await Task.sleep(nanoseconds: responseAfterThinkingTimeoutSeconds * 1_000_000_000)
            guard !Task.isCancelled, let appState else { return }
            if appState.clientState == .thinking {
                appState.setError("Assistant is still thinking for too long. Please try again.")
            }
        }
    }

    private func cancelResponseTimeout() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
    }

    private func ensureConnected(appState: AppState) async -> Bool {
        switch appState.connectionStatus {
        case .connected:
            return true
        case .disconnected:
            await connectIfNeeded(appState: appState)
            return appState.connectionStatus == .connected
        case .connecting:
            for _ in 0..<12 {
                if appState.connectionStatus == .connected {
                    return true
                }
                if appState.connectionStatus == .disconnected {
                    return false
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            return appState.connectionStatus == .connected
        }
    }
}
