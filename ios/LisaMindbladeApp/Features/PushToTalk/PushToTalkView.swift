import SwiftUI

struct PushToTalkView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var connectionManager: ConnectionManager

    private var isListening: Bool {
        appState.clientState == .listening
    }

    private var isThinking: Bool {
        appState.clientState == .thinking
    }

    private var isSpeaking: Bool {
        appState.clientState == .speaking
    }

    private var shouldShowLisaFigure: Bool {
        isThinking || isSpeaking || appState.isPlaybackActive
    }

    private var canToggleCapture: Bool {
        isListening || (
            appState.connectionStatus == .connected &&
            (appState.clientState == .idle || appState.clientState == .error)
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Lisa")
                .font(.largeTitle.bold())

            if let statusText {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if !appState.liveTranscript.isEmpty {
                Text(appState.liveTranscript)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 24)
            }

            if shouldShowLisaFigure {
                Button {
                    Task {
                        await connectionManager.interruptAndStartPushToTalk(appState: appState)
                    }
                } label: {
                    LisaActiveFigureView(isSpeaking: isSpeaking)
                        .frame(width: 250, height: 250)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Interrupt Lisa and speak")
                .accessibilityHint("Double tap to stop Lisa and start listening")
            } else {
                SunRecordButton(isListening: isListening, isThinking: isThinking) {
                    Task {
                        if isListening {
                            await connectionManager.stopPushToTalk(appState: appState, transcript: "")
                        } else {
                            appState.liveTranscript = ""
                            await connectionManager.startPushToTalk(appState: appState)
                        }
                    }
                }
                .disabled(!canToggleCapture)
                .opacity(canToggleCapture ? 1 : 0.55)
            }

            if appState.clientState == .awaitingConfirmation, let pendingAction = appState.pendingAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pendingAction.title)
                        .font(.headline)
                    Text(pendingAction.summary)
                        .foregroundStyle(.secondary)
                    Button("Confirm") {
                        Task { await connectionManager.confirmPendingAction(appState: appState) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 20)
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()

            Text("Connection: \(appState.connectionStatus.rawValue)")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
        .padding(.bottom, 24)
    }

    private var statusText: String? {
        switch appState.clientState {
        case .listening:
            return "Listening..."
        case .transcribing:
            return "Transcribing..."
        case .thinking:
            return "Thinking..."
        case .speaking:
            return "Speaking..."
        case .awaitingConfirmation:
            return "Awaiting confirmation"
        case .error:
            return "Something went wrong"
        case .idle:
            return nil
        }
    }
}

private struct LisaActiveFigureView: View {
    let isSpeaking: Bool
    @State private var anchorDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(anchorDate))
            let breathe = 1.0 + (sin(elapsed * 2.2) + 1.0) * 0.015
            let bob = sin(elapsed * 1.4) * 5.0
            let sway = sin(elapsed * 0.9) * 1.2
            let haloSpin = elapsed * (isSpeaking ? 24.0 : 16.0)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.95, green: 0.55, blue: 0.12).opacity(0.40),
                                Color(red: 0.60, green: 0.25, blue: 0.02).opacity(0.32),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 150
                        )
                    )
                    .frame(width: 280, height: 280)

                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.88),
                                .yellow.opacity(0.85),
                                .orange.opacity(0.78),
                                .white.opacity(0.88),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round, dash: [2, 9])
                    )
                    .frame(width: 236, height: 236)
                    .rotationEffect(.degrees(haloSpin))

                Circle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 206, height: 206)
                    .blur(radius: 2.0)

                Image("LisaActiveFigure")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 206, height: 206)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.72), lineWidth: 2.0)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.orange.opacity(0.65), lineWidth: 6.0)
                            .blur(radius: 7.0)
                    )
                    .shadow(color: Color.orange.opacity(0.65), radius: 30)
            }
            .frame(width: 280, height: 280)
            .scaleEffect(breathe)
            .rotationEffect(.degrees(sway))
            .offset(y: bob)
        }
        .onAppear {
            anchorDate = Date()
        }
        .accessibilityLabel(isSpeaking ? "Lisa is speaking" : "Lisa is thinking")
    }
}

private struct SunRecordButton: View {
    let isListening: Bool
    let isThinking: Bool
    let onTap: () -> Void

    @State private var anchorDate = Date()

    var body: some View {
        Button {
            if !isListening && !isThinking {
                anchorDate = Date()
            }
            onTap()
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(anchorDate))
                let isAnimating = isListening || isThinking
                let spin = isAnimating ? elapsed * (isThinking ? 30 : 22) : 0
                let reverseSpin = isAnimating ? -elapsed * (isThinking ? 16 : 12) : 0
                let pulse = isListening ? (sin(elapsed * 3.0) + 1) / 2 : (isThinking ? (sin(elapsed * 2.0) + 1) / 5 : 0)
                let jitter = isListening ? (sin(elapsed * 8.0) + 1) / 2 : (isThinking ? (sin(elapsed * 4.5) + 1) / 2 : 0)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.black.opacity(0.55),
                                    Color(red: 0.13, green: 0.06, blue: 0.0).opacity(0.45),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 130
                            )
                        )
                        .frame(width: 250, height: 250)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isListening ? 0.65 : 0.36),
                                    (isThinking ? Color.red : Color.yellow).opacity(isAnimating ? 0.58 : 0.30),
                                    (isThinking ? Color.orange : Color.orange).opacity(isAnimating ? 0.40 : 0.18),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 128
                            )
                        )
                        .frame(width: 244, height: 244)

                    ForEach(0..<24, id: \.self) { index in
                        let angle = Double(index) * (360.0 / 24.0) + (spin * 0.55)
                        let dynamicLength = 14 + (isListening ? CGFloat((sin(elapsed * 5.0 + Double(index)) + 1) * 10) : 0)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [(isThinking ? Color.red : Color.yellow).opacity(isAnimating ? 0.98 : 0.56), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2.2, height: dynamicLength)
                            .offset(y: -118)
                            .rotationEffect(.degrees(angle))
                            .opacity(isListening ? 0.98 : 0.35)
                    }

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    (isThinking ? Color.red : Color.yellow).opacity(0.9),
                                    Color.orange.opacity(0.8),
                                    Color.white.opacity(0.95),
                                    (isThinking ? Color.red : Color.yellow).opacity(0.9),
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.8, lineCap: .round, dash: [2.0, 8.0])
                        )
                        .frame(width: 220, height: 220)
                        .rotationEffect(.degrees(spin))
                        .opacity(isListening ? 0.98 : 0.62)

                    Circle()
                        .trim(from: 0.07, to: 0.91)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    (isThinking ? Color.red : Color.yellow).opacity(0.7),
                                    Color.orange.opacity(0.8),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .frame(width: 236, height: 236)
                        .rotationEffect(.degrees(reverseSpin))
                        .opacity(isListening ? 0.92 : 0.52)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.99),
                                    (isThinking ? Color.red : Color.yellow).opacity(0.97),
                                    Color.orange.opacity(0.92),
                                    Color(red: 0.80, green: 0.34, blue: 0.0).opacity(0.94),
                                ],
                                center: .center,
                                startRadius: 7,
                                endRadius: 82
                            )
                        )
                        .frame(width: 172, height: 172)
                        .overlay(
                            Circle()
                                .fill(
                                    AngularGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            (isThinking ? Color.red : Color.yellow).opacity(0.5),
                                            Color.orange.opacity(0.35),
                                            Color.white.opacity(0.2),
                                        ],
                                        center: .center
                                    )
                                )
                                .blur(radius: 1.2)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isListening ? 0.95 : 0.65), lineWidth: 4.0)
                                .blur(radius: 0.6)
                        )
                        .shadow(color: .orange.opacity(isAnimating ? 0.95 : 0.62), radius: isAnimating ? 32 : 18)
                        .shadow(color: (isThinking ? Color.red : Color.yellow).opacity(isAnimating ? 0.78 : 0.38), radius: isAnimating ? 56 : 28)

                    ForEach(0..<10, id: \.self) { index in
                        let phase = elapsed * 3.2 + Double(index) * 0.8
                        let angle = (Double(index) * 36.0) + spin
                        let radius: CGFloat = 102 + (isListening ? CGFloat((sin(phase) + 1) * 9) : 0)
                        let size: CGFloat = isListening ? 2.5 + CGFloat(jitter * 2.5) : 2

                        Circle()
                            .fill(Color.white.opacity(isAnimating ? 0.9 : 0))
                            .frame(width: size, height: size)
                            .offset(
                                x: radius * CGFloat(cos(angle * .pi / 180)),
                                y: radius * CGFloat(sin(angle * .pi / 180))
                            )
                            .shadow(color: (isThinking ? Color.red : Color.yellow).opacity(0.8), radius: 3)
                    }
                }
                .frame(width: 250, height: 250)
                .scaleEffect(isAnimating ? (1.0 + (pulse * 0.045)) : 1.0)
                .offset(y: isAnimating ? CGFloat(sin(elapsed * 1.7) * 3.0) : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Stop listening" : "Start listening")
        .accessibilityHint("Double tap to toggle voice capture")
    }
}
