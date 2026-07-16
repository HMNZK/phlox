import Foundation
import AgentDomain

struct HookPayload: Decodable, Sendable {
    let sessionId: String
    let kind: String
    let message: String?
    let toolName: String?
    let turnId: String?
    let nativeSessionId: String?
}

enum HookPayloadError: Error, Sendable, LocalizedError {
    case invalidSessionId
    case unknownKind(String)
    case missingMessage
    case missingToolName

    var errorDescription: String? {
        switch self {
        case .invalidSessionId:
            "invalid sessionId"
        case let .unknownKind(kind):
            "unknown kind: \(kind)"
        case .missingMessage:
            "message is required for notification"
        case .missingToolName:
            "toolName is required"
        }
    }
}

extension HookPayload {
    func makeEvent() throws -> (SessionID, HookEvent) {
        let delivery = try makeDelivery()
        return (delivery.sessionID, delivery.event)
    }

    func makeDelivery() throws -> HookDelivery {
        guard let uuid = UUID(uuidString: sessionId) else {
            throw HookPayloadError.invalidSessionId
        }
        let sessionID = SessionID(rawValue: uuid)
        let event: HookEvent

        switch kind {
        case "sessionStart":
            event = .sessionStart
        case "notification":
            guard let message else { throw HookPayloadError.missingMessage }
            event = .notification(message: message)
        case "stop":
            event = .stop(turnId: turnId)
        case "preToolUse":
            guard let toolName else { throw HookPayloadError.missingToolName }
            event = .preToolUse(toolName: toolName)
        case "postToolUse":
            guard let toolName else { throw HookPayloadError.missingToolName }
            event = .postToolUse(toolName: toolName)
        case "userPromptSubmit":
            event = .userPromptSubmit(turnId: turnId)
        default:
            throw HookPayloadError.unknownKind(kind)
        }

        return HookDelivery(
            sessionID: sessionID,
            event: event,
            nativeSessionId: nativeSessionId?.isEmpty == false ? nativeSessionId : nil
        )
    }
}
