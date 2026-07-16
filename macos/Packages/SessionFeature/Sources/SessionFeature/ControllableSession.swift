import Foundation
import AgentDomain

public enum ControllableSessionError: Error, Sendable {
    case notSpawned
    case unsupportedPartialInput
}

@MainActor
public protocol ControllableSession: AnyObject {
    var id: SessionID { get }
    var name: String { get set }
    var displayName: String { get }
    var status: SessionStatus { get }
    var completedTurnSeq: Int { get }
    var lastOutputAt: Date? { get }
    var lastTurnCompletedAt: Date? { get }
    var submitBaselineTurnSeq: Int? { get }
    var isReadyForInput: Bool { get }
    var parentSessionID: SessionID? { get set }
    var launchContext: SessionLaunchContext { get set }

    func sendText(_ text: String, submit: Bool) async throws
    func consumeSubmitBaseline()
    func readText(lines: Int) -> String
    func terminate() async
}

@MainActor
public enum SessionNode {
    case pty(SessionViewModel)
    case appServer(ChatSessionViewModel)

    public var id: SessionID { controllable.id }

    public var startedAt: Date {
        switch self {
        case .pty(let session):
            session.startedAt
        case .appServer(let session):
            session.startedAt
        }
    }

    public var displayName: String { controllable.displayName }

    public var name: String {
        get { controllable.name }
        nonmutating set { controllable.name = newValue }
    }

    public var status: SessionStatus { controllable.status }

    /// 直近の PTY/Chat 出力時刻を委譲で公開する読み取り専用アクセサ（`status` と同型）。
    public var lastOutputAt: Date? { controllable.lastOutputAt }

    public var agentDescriptor: AgentDescriptor {
        switch self {
        case .pty(let session):
            return session.agentDescriptor
        case .appServer(let session):
            if let kind = session.agentRef.builtinKind {
                return AgentRegistry.descriptor(for: kind)
            }
            return AgentDescriptor(
                ref: session.agentRef,
                displayName: session.agentRef.id,
                binaryName: session.agentRef.id,
                symbolName: "terminal",
                colorRGB: AgentRGB(0x8A, 0x8F, 0x98),
                bypassKey: "phlox.bypass.\(session.agentRef.id)",
                launchSpec: AgentLaunchSpec(statusBootstrap: .idleOnSpawnComplete)
            )
        }
    }

    public var controllable: any ControllableSession {
        switch self {
        case .pty(let session):
            session
        case .appServer(let session):
            session
        }
    }

    public var agentRef: AgentRef {
        switch self {
        case .pty(let session):
            session.agentRef
        case .appServer(let session):
            session.agentRef
        }
    }

    public var projectID: ProjectID? {
        get {
            switch self {
            case .pty(let session):
                session.projectID
            case .appServer(let session):
                session.projectID
            }
        }
        nonmutating set {
            switch self {
            case .pty(let session):
                session.projectID = newValue
            case .appServer(let session):
                session.projectID = newValue
            }
        }
    }

    public var launchContext: SessionLaunchContext {
        get {
            switch self {
            case .pty(let session):
                session.launchContext
            case .appServer(let session):
                session.launchContext
            }
        }
        nonmutating set {
            switch self {
            case .pty(let session):
                session.launchContext = newValue
            case .appServer(let session):
                session.launchContext = newValue
            }
        }
    }

    public var workspaceName: String {
        switch self {
        case .pty(let session):
            session.workspaceName
        case .appServer(let session):
            session.workspaceName
        }
    }

    public var workspacePath: String {
        switch self {
        case .pty(let session):
            session.workspacePath
        case .appServer(let session):
            session.workspacePath
        }
    }

    public var appServer: ChatSessionViewModel? {
        if case .appServer(let session) = self { session } else { nil }
    }

    public var pty: SessionViewModel? {
        if case .pty(let session) = self { session } else { nil }
    }
}
