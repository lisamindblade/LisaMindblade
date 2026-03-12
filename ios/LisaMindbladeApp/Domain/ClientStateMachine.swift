import Foundation

enum LisaClientState: String, CaseIterable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case awaitingConfirmation
    case error
}

enum ClientStateEvent {
    case startListening
    case stopListening
    case transcriptSent
    case receivedThinking
    case receivedChunk
    case receivedFinalResponse
    case speechPlaybackFinished
    case confirmationRequired
    case actionConfirmed
    case cancel
    case sessionEnded
    case failure
}

struct LisaClientStateMachine {
    private(set) var state: LisaClientState = .idle

    mutating func transition(with event: ClientStateEvent) -> LisaClientState {
        switch event {
        case .startListening:
            state = .listening
        case .stopListening:
            if state == .listening {
                state = .transcribing
            }
        case .transcriptSent:
            if state == .transcribing {
                state = .thinking
            }
        case .receivedThinking:
            state = .thinking
        case .receivedChunk:
            state = .speaking
        case .receivedFinalResponse:
            // Keep speaking state until local TTS playback actually ends.
            if state != .speaking {
                state = .speaking
            }
        case .speechPlaybackFinished:
            state = .idle
        case .confirmationRequired:
            state = .awaitingConfirmation
        case .actionConfirmed:
            state = .thinking
        case .cancel, .sessionEnded:
            state = .idle
        case .failure:
            state = .error
        }
        return state
    }
}
