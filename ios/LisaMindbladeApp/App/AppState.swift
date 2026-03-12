import Foundation

enum ConnectionStatus: String {
    case disconnected
    case connecting
    case connected
}

struct PendingAction: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let reason: String
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var clientState: LisaClientState = .idle
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var surface: Surface = .iphone
    @Published var liveTranscript: String = ""
    @Published var transcriptHistory: [String] = []
    @Published var streamingAssistantText: String = ""
    @Published var assistantHistory: [String] = []
    @Published var pendingAction: PendingAction?
    @Published var errorMessage: String?
    @Published var isPlaybackActive: Bool = false

    private var stateMachine = LisaClientStateMachine()

    func apply(_ event: ClientStateEvent) {
        clientState = stateMachine.transition(with: event)
        if clientState != .error {
            errorMessage = nil
        }
    }

    func setError(_ message: String) {
        errorMessage = message
        clientState = stateMachine.transition(with: .failure)
    }

    func setSurface(_ value: Surface) {
        surface = value
    }

    func setPendingAction(_ action: PendingAction?) {
        pendingAction = action
    }

    func setPlaybackActive(_ value: Bool) {
        isPlaybackActive = value
    }

    func clearStreamingAssistantText() {
        streamingAssistantText = ""
    }
}
