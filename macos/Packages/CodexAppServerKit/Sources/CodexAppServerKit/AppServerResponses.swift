// JSON-RPC レスポンス型。
import Foundation

public struct InitializeResponse: Codable, Equatable, Sendable {
    public var codexHome: String
    public var platformFamily: String
    public var platformOs: String
    public var userAgent: String
}

public struct ThreadResponse: Codable, Equatable, Sendable {
    public var thread: ThreadSummary
    public var cwd: String?
    public var model: String?
    public var modelProvider: String?
    public var reasoningEffort: String?
    public var activePermissionProfile: ActivePermissionProfile?
    public var approvalPolicy: ApprovalPolicy?
    public var approvalsReviewer: String?
    public var sandbox: SandboxPolicy?
    public var serviceTier: String?
}

public struct ThreadReadResponse: Codable, Equatable, Sendable {
    public var thread: ThreadSummary
}

public struct TurnStartResponse: Codable, Equatable, Sendable {}

public struct TurnInterruptResponse: Codable, Equatable, Sendable {}

public struct ModelListResponse: Codable, Equatable, Sendable {
    public var data: [AppServerModel]
    public var nextCursor: String?
}

public struct PermissionProfileListResponse: Codable, Equatable, Sendable {
    public var data: [PermissionProfileSummary]
    public var nextCursor: String?
}

public struct CollaborationModeListResponse: Codable, Equatable, Sendable {
    public var data: [CollaborationModeMask]
}

public struct ThreadSettingsUpdateResponse: Codable, Equatable, Sendable {
    public init() {}
}
