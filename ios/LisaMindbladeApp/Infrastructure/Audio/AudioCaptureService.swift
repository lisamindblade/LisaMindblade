import AVFoundation
import Foundation
import Speech

@MainActor
final class ConversationAudioSession {
    static let shared = ConversationAudioSession()

    private var isActive = false

    private init() {}

    func activateIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Keep one stable audio profile for both STT and TTS to avoid mode churn.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.duckOthers, .defaultToSpeaker]
            )
            if !isActive {
                try session.setActive(true)
                isActive = true
            }
        } catch {
            // Keep audio setup non-fatal for UI/testing flow.
        }
    }
}

struct CapturedAudioResult {
    let transcriptCandidate: String?
}

@MainActor
protocol AudioCapturing {
    var onPartialTranscript: ((String) -> Void)? { get set }

    func startCapture() async throws
    func stopCapture() async throws -> CapturedAudioResult
    func cancelCapture()
}

enum AudioCaptureError: LocalizedError {
    case speechRecognizerUnavailable
    case speechAuthorizationDenied
    case microphonePermissionDenied
    case audioEngineNotRunning

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available for the current locale."
        case .speechAuthorizationDenied:
            return "Speech recognition permission was denied."
        case .microphonePermissionDenied:
            return "Microphone permission was denied."
        case .audioEngineNotRunning:
            return "Audio engine is not running."
        }
    }
}

@MainActor
final class AppleSpeechAudioCaptureService: AudioCapturing {
    var onPartialTranscript: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript: String = ""
    private let preferredLocale: Locale

    init(locale: Locale = .current) {
        preferredLocale = locale
        speechRecognizer = Self.makeRecognizer(preferredLocale: locale)
    }

    func startCapture() async throws {
        try await requestPermissionsIfNeeded()
        guard let speechRecognizer = resolveRecognizer(), speechRecognizer.isAvailable else {
            throw AudioCaptureError.speechRecognizerUnavailable
        }

        cancelCapture()
        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        ConversationAudioSession.shared.activateIfNeeded()

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard buffer.frameLength > 0 else {
                return
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let hasBytes = bufferList.contains { $0.mDataByteSize > 0 }
            guard hasBytes else {
                return
            }
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.latestTranscript = text
                    self.onPartialTranscript?(text)
                }
            }
        }
    }

    func stopCapture() async throws -> CapturedAudioResult {
        guard audioEngine.isRunning else {
            throw AudioCaptureError.audioEngineNotRunning
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Give the recognizer a short window to produce a final transcript.
        try? await Task.sleep(nanoseconds: 250_000_000)

        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return CapturedAudioResult(transcriptCandidate: transcript.isEmpty ? nil : transcript)
    }

    func cancelCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func requestPermissionsIfNeeded() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw AudioCaptureError.speechAuthorizationDenied
        }

        let micAllowed = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        guard micAllowed else {
            throw AudioCaptureError.microphonePermissionDenied
        }
    }

    private func resolveRecognizer() -> SFSpeechRecognizer? {
        if let recognizer = speechRecognizer, recognizer.isAvailable {
            return recognizer
        }

        let fallback = Self.makeRecognizer(preferredLocale: preferredLocale)
        speechRecognizer = fallback
        return fallback
    }

    private static func makeRecognizer(preferredLocale: Locale) -> SFSpeechRecognizer? {
        let supportedLocales = SFSpeechRecognizer.supportedLocales()

        if supportedLocales.contains(where: { $0.identifier == preferredLocale.identifier }) {
            return SFSpeechRecognizer(locale: preferredLocale)
        }

        if let preferredLanguageCode = preferredLocale.language.languageCode?.identifier,
           let sameLanguage = supportedLocales.first(where: {
               $0.language.languageCode?.identifier == preferredLanguageCode
           }) {
            return SFSpeechRecognizer(locale: sameLanguage)
        }

        if let english = supportedLocales.first(where: { $0.identifier == "en_US" || $0.identifier == "en-US" }) {
            return SFSpeechRecognizer(locale: english)
        }

        if let firstSupportedLocale = supportedLocales.first {
            return SFSpeechRecognizer(locale: firstSupportedLocale)
        }

        return nil
    }

}

@MainActor
final class StubAudioCaptureService: AudioCapturing {
    var onPartialTranscript: ((String) -> Void)?

    func startCapture() async throws {
        // Placeholder capture service for tests.
    }

    func stopCapture() async throws -> CapturedAudioResult {
        CapturedAudioResult(transcriptCandidate: nil)
    }

    func cancelCapture() {
        // No-op.
    }
}
