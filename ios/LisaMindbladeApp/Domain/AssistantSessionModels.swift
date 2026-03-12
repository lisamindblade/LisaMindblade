import Foundation

enum Surface: String, Codable {
    case iphone
    case carplay
    case watch
}

enum ClientEventType: String, Codable {
    case sessionStart = "session.start"
    case transcriptPartial = "transcript.partial"
    case transcriptFinal = "transcript.final"
    case sessionEnd = "session.end"
}

enum ServerEventType: String, Codable {
    case assistantThinking = "assistant.thinking"
    case assistantResponseChunk = "assistant.response.chunk"
    case assistantResponseFinal = "assistant.response.final"
    case actionProposed = "action.proposed"
    case actionConfirmationRequired = "action.confirmation_required"
    case sessionEnd = "session.end"
    case error
}

struct EmptyPayload: Codable {}

struct SessionStartPayload: Codable {
    let clientVersion: String?
    let deviceID: String?
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case clientVersion = "client_version"
        case deviceID = "device_id"
        case authToken = "auth_token"
    }
}

struct TranscriptPayload: Codable {
    let text: String
}

struct SessionEndPayload: Codable {
    let reason: String?
}

struct AssistantThinkingPayload: Codable {
    let message: String
}

struct AssistantResponseChunkPayload: Codable {
    let turnID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case text
    }
}

struct AssistantResponseFinalPayload: Codable {
    let turnID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case text
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct ActionProposedPayload: Codable {
    let actionType: String
    let parameters: [String: JSONValue]
    let actionID: String
    let title: String
    let summary: String
    let risk: String
    let requiresConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case actionType = "action_type"
        case parameters
        case actionID = "action_id"
        case title
        case summary
        case risk
        case requiresConfirmation = "requires_confirmation"
    }
}

struct ActionConfirmationRequiredPayload: Codable {
    let actionID: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case reason
    }
}

struct ErrorPayload: Codable {
    let code: String
    let message: String
    let details: [String: JSONValue]?
}

struct ClientEventEnvelope<Payload: Encodable>: Encodable {
    let version: String
    let eventID: String
    let timestamp: Date
    let sessionID: String
    let surface: Surface
    let type: ClientEventType
    let payload: Payload

    init(
        version: String = "1.0",
        eventID: String = UUID().uuidString,
        timestamp: Date = Date(),
        sessionID: String,
        surface: Surface,
        type: ClientEventType,
        payload: Payload
    ) {
        self.version = version
        self.eventID = eventID
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.surface = surface
        self.type = type
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case version
        case eventID = "event_id"
        case timestamp
        case sessionID = "session_id"
        case surface
        case type
        case payload
    }
}

struct ServerEventEnvelope<Payload: Decodable>: Decodable {
    let version: String
    let eventID: String
    let timestamp: Date
    let sessionID: String
    let surface: Surface
    let type: ServerEventType
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case version
        case eventID = "event_id"
        case timestamp
        case sessionID = "session_id"
        case surface
        case type
        case payload
    }
}

enum ServerEvent {
    case assistantThinking(ServerEventEnvelope<AssistantThinkingPayload>)
    case assistantResponseChunk(ServerEventEnvelope<AssistantResponseChunkPayload>)
    case assistantResponseFinal(ServerEventEnvelope<AssistantResponseFinalPayload>)
    case actionProposed(ServerEventEnvelope<ActionProposedPayload>)
    case actionConfirmationRequired(ServerEventEnvelope<ActionConfirmationRequiredPayload>)
    case sessionEnd(ServerEventEnvelope<SessionEndPayload>)
    case error(ServerEventEnvelope<ErrorPayload>)
}

enum ServerEventParser {
    static func parse(from data: Data) throws -> ServerEvent {
        let decoder = JSONDecoder.lisaProtocolDecoder
        let baseEnvelope = try decoder.decode(ServerEventEnvelope<EmptyPayload>.self, from: data)

        switch baseEnvelope.type {
        case .assistantThinking:
            return .assistantThinking(try decoder.decode(ServerEventEnvelope<AssistantThinkingPayload>.self, from: data))
        case .assistantResponseChunk:
            return .assistantResponseChunk(try decoder.decode(ServerEventEnvelope<AssistantResponseChunkPayload>.self, from: data))
        case .assistantResponseFinal:
            return .assistantResponseFinal(try decoder.decode(ServerEventEnvelope<AssistantResponseFinalPayload>.self, from: data))
        case .actionProposed:
            return .actionProposed(try decoder.decode(ServerEventEnvelope<ActionProposedPayload>.self, from: data))
        case .actionConfirmationRequired:
            return .actionConfirmationRequired(try decoder.decode(ServerEventEnvelope<ActionConfirmationRequiredPayload>.self, from: data))
        case .sessionEnd:
            return .sessionEnd(try decoder.decode(ServerEventEnvelope<SessionEndPayload>.self, from: data))
        case .error:
            return .error(try decoder.decode(ServerEventEnvelope<ErrorPayload>.self, from: data))
        }
    }
}

extension JSONEncoder {
    static var lisaProtocolEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var lisaProtocolDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
