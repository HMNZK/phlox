import Foundation
import AgentDomain

public enum ControllableSessionError: Error, Sendable {
    case notSpawned
    case unsupportedPartialInput
}

/// ユーザーへの働きかけの届け先。
public enum UserNotificationChannel: Sendable, Equatable {
    /// macOS の通知バナー・完了音。
    case local
    /// APNs（iPhone へ届く）。
    case remote
}

@MainActor
public protocol ControllableSession: AnyObject {
    var id: SessionID { get }
    var name: String { get set }
    var displayName: String { get }
    var status: SessionStatus { get }
    var isProcessing: Bool { get }
    var displayStatus: SessionStatus { get }
    var completedTurnSeq: Int { get }
    var lastOutputAt: Date? { get }
    var lastTurnCompletedAt: Date? { get }
    var submitBaselineTurnSeq: Int? { get }
    var isReadyForInput: Bool { get }
    var parentSessionID: SessionID? { get set }
    var launchContext: SessionLaunchContext { get set }

    /// 未確認の停止（＝ユーザーの対応待ち）。停止状態へ入るとラッチし、選択（閲覧）で解除する。
    var hasUnseenCompletion: Bool { get }
    /// `hasUnseenCompletion` の変化通知フック（Dock バッジ等の集計更新に使う）。
    var unseenCompletionDidChange: (() -> Void)? { get set }
    /// チャネルごとに、ユーザーへの働きかけを出してよいか。
    /// nil のときは全チャネル通知する（既定＝既存挙動）。
    var userNotificationGate: ((UserNotificationChannel) -> Bool)? { get set }

    func sendText(_ text: String, submit: Bool) async throws
    func consumeSubmitBaseline()
    func readText(lines: Int) -> String
    /// 端末画面を SGR（色・装飾）付きで返す。端末を持たないセッション（構造化 appServer）は nil。
    func readAnsiScreen() -> AnsiScreen?
    func terminate() async
    /// 未確認停止を「確認済み」にする（選択・閲覧時に呼ぶ）。
    func markCompletionSeen()
}

public extension ControllableSession {
    var displayStatus: SessionStatus {
        SessionDisplayStatus.resolve(rawStatus: status, isProcessing: isProcessing)
    }

    /// 既定は「端末を持たない」。PTY セッションだけが上書きする。
    func readAnsiScreen() -> AnsiScreen? { nil }
}

/// 端末画面のスナップショット。モバイルが同じ桁数・同じ色で描き直すために使う。
///
/// `readText` のプレーンテキストと違い、色・太字・反転が落ちない。`cols` はデスクトップの
/// 端末幅で、受け手はこの桁数で描かないと折り返し位置がずれる。
public struct AnsiScreen: Sendable, Equatable {
    /// SGR を含む画面テキスト。行区切りは `\n`。
    public let ansi: String
    public let cols: Int

    public init(ansi: String, cols: Int) {
        self.ansi = ansi
        self.cols = cols
    }
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

    public var displayStatus: SessionStatus { controllable.displayStatus }

    /// 未確認の停止（＝ユーザーの対応待ち）。PTY / Chat どちらの種別でも共通に読める。
    public var hasUnseenCompletion: Bool { controllable.hasUnseenCompletion }

    /// 未確認停止を「確認済み」にする（選択・閲覧時に呼ぶ）。
    public func markCompletionSeen() { controllable.markCompletionSeen() }

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
