import Foundation
import AgentDomain
import CodexAppServerKit

// Hidden secret: session DTOs and app-server conversion adapters shared by chat sessions.
public enum ChatApprovalKind: Sendable, Equatable {
    case command
    case fileChange
    case permissions
}

public struct ChatApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ChatApprovalKind
    public let threadId: String
    public let turnId: String
    public let itemId: String
    public let prompt: String
}

public struct RunningBackgroundTask: Identifiable, Equatable, Sendable {
    public let taskId: String
    public let taskType: String
    public let description: String
    public let startedAt: Date
    public let toolUseId: String?

    public var id: String { taskId }
}

struct SubAgentTranscriptFileMetadata: Equatable {
    let modifiedAt: Date?
    let size: Int
}

struct CachedSubAgentTranscript {
    let metadata: SubAgentTranscriptFileMetadata
    let items: [ChatItem]
}

public enum ChatRestoreState: Equatable, Sendable {
    case notRestored
    case restored
    case failed(message: String)
}

public enum ChatNativeSessionIDNotification {
    public static let name = Notification.Name("DashboardFeature.ChatNativeSessionIDDidChange")
    public static let sessionIDKey = "sessionID"
    public static let nativeSessionIDKey = "nativeSessionID"
}

public enum ChatSettingsUpdateError: Error, Equatable, Sendable {
    case threadNotStarted
    case planModeUnavailable
    case codexSettingsUnavailable
}

public protocol CodexSettingsProviding: Sendable {
    var threadEvents: AsyncStream<ThreadEvent> { get }

    /// 現在アクティブな thread id。reset 後の新 thread を VM が採用し、旧 thread の遅延イベントを
    /// 弁別するために参照する。
    func activeThreadId() async -> String?
    func initialize(_ params: InitializeParams) async throws -> InitializeResponse
    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse
    func listModels(_ params: ModelListParams) async throws -> ModelListResponse
    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse
    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse
    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse
}

extension CodexStructuredAgentClient: CodexSettingsProviding {}

extension ThreadStatus {
    var isWaitingOnApproval: Bool {
        if case .active(let flags) = self {
            flags.contains { $0 == "waitingOnApproval" }
        } else {
            false
        }
    }

    var sessionStatus: SessionStatus {
        switch self {
        case .idle, .notLoaded:
            .idle
        case .systemError:
            .error(message: "app-server system error")
        case .active:
            isWaitingOnApproval ? .awaitingApproval(prompt: "Approval requested") : .running
        case .unknown(let value):
            .error(message: "unknown app-server status: \(value)")
        }
    }
}

extension JSONValue {
    func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue {
                return value
            }
        }
        if case .array(let values) = self {
            for value in values {
                if let text = value.firstString(for: keys) {
                    return text
                }
            }
        }
        return nil
    }
}
