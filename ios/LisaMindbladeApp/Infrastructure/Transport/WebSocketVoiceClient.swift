import Foundation

protocol VoiceTransport: AnyObject {
    var supportsServerPush: Bool { get }
    var onServerEvent: ((Result<ServerEvent, Error>) -> Void)? { get set }

    func connect() async throws
    func send<Payload: Encodable>(event: ClientEventEnvelope<Payload>) async throws
    func disconnect() async
}

enum VoiceTransportError: LocalizedError {
    case notConnected
    case encodeFailure
    case unsupportedServerMessage

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No active WebSocket connection."
        case .encodeFailure:
            return "Failed to encode outbound protocol message."
        case .unsupportedServerMessage:
            return "Received unsupported WebSocket frame from server."
        }
    }
}

final class WebSocketVoiceClient: VoiceTransport {
    var supportsServerPush: Bool { true }
    var onServerEvent: ((Result<ServerEvent, Error>) -> Void)?

    private let backendURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder.lisaProtocolEncoder
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(backendURL: URL? = nil, session: URLSession = .shared) {
        self.backendURL = backendURL ?? Self.resolveBackendURL()
        self.session = session
    }

    deinit {
        receiveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
    }

    func connect() async throws {
        if socketTask != nil {
            return
        }

        let task = session.webSocketTask(with: backendURL)
        socketTask = task
        task.resume()

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(for: task)
        }
    }

    func send<Payload: Encodable>(event: ClientEventEnvelope<Payload>) async throws {
        guard let socketTask else {
            throw VoiceTransportError.notConnected
        }

        let encoded = try encoder.encode(event)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw VoiceTransportError.encodeFailure
        }

        try await socketTask.send(.string(payload))
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
    }

    private func runReceiveLoop(for task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let payloadData: Data

                switch message {
                case .string(let text):
                    payloadData = Data(text.utf8)
                case .data(let data):
                    payloadData = data
                @unknown default:
                    throw VoiceTransportError.unsupportedServerMessage
                }

                let event = try ServerEventParser.parse(from: payloadData)
                if let onServerEvent {
                    DispatchQueue.main.async {
                        onServerEvent(.success(event))
                    }
                }
            } catch {
                if Task.isCancelled {
                    break
                }
                if let onServerEvent {
                    DispatchQueue.main.async {
                        onServerEvent(.failure(error))
                    }
                }
                break
            }
        }

        if socketTask === task {
            socketTask = nil
        }
    }

    private static func resolveBackendURL() -> URL {
        if let envURLString = ProcessInfo.processInfo.environment["LISAMINDBLADE_BACKEND_WS_URL"],
           let url = URL(string: envURLString) {
            return url
        }

        if let defaultsURLString = UserDefaults.standard.string(forKey: "LisaMindbladeBackendWSURL"),
           let url = URL(string: defaultsURLString) {
            return url
        }

        return URL(string: "wss://lisa.taild3cb8f.ts.net")!
    }
}
