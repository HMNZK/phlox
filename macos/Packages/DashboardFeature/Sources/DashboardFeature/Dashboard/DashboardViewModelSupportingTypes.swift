import Foundation
import AgentDomain
import CodexAppServerKit
import StructuredChatKit

// 隠している秘密: DashboardViewModel 本体の責務ではない表示値・エラー型・復元失敗用 no-op client。

public struct RestoredSessionPresentation: Sendable, Equatable {
    public let selectedSessionID: SessionID
    public let expandedProjectIDs: Set<ProjectID>

    public init(selectedSessionID: SessionID, expandedProjectIDs: Set<ProjectID>) {
        self.selectedSessionID = selectedSessionID
        self.expandedProjectIDs = expandedProjectIDs
    }
}

/// プロジェクト削除確認ダイアログの文言（09 D4 / 03 F8）。View 直テストが困難なため純関数として切り出す。
/// 件数には、この一覧に出ない別プロジェクトの子孫も含める（一緒に消えるため）。
public enum ProjectDeletionDialogText {
    public static func title(projectName: String) -> String {
        "プロジェクト「\(projectName)」を削除しますか?"
    }

    /// `sessionCount` と `childCount` はこのプロジェクトの分、`otherProjectChildCount` はほかのプロジェクトにある子孫（一緒に消える）。
    public static func message(sessionCount: Int, childCount: Int, otherProjectChildCount: Int = 0) -> String {
        let (format, args) = messageFormat(sessionCount: sessionCount, childCount: childCount, otherProjectChildCount: otherProjectChildCount)
        return String(format: format, arguments: args)
    }

    static func messageFormat(sessionCount: Int, childCount: Int, otherProjectChildCount: Int) -> (String, [CVarArg]) {
        switch (sessionCount > 0, childCount > 0, otherProjectChildCount > 0) {
        case (false, _, _):
            ("このプロジェクトを一覧から外します。", [])
        case (true, true, true):
            ("このプロジェクトのセッション %lld 件（子セッション %lld 件を含む）と、ほかのプロジェクトにある子セッション %lld 件を停止し、一覧から外します。会話は元に戻せません。",
             [sessionCount, childCount, otherProjectChildCount])
        case (true, false, true):
            ("このプロジェクトのセッション %lld 件と、ほかのプロジェクトにある子セッション %lld 件を停止し、一覧から外します。会話は元に戻せません。",
             [sessionCount, otherProjectChildCount])
        case (true, true, false):
            ("このプロジェクトのセッション %lld 件（子セッション %lld 件を含む）を停止し、一覧から外します。会話は元に戻せません。",
             [sessionCount, childCount])
        case (true, false, false):
            ("このプロジェクトのセッション %lld 件を停止し、一覧から外します。会話は元に戻せません。", [sessionCount])
        }
    }

    public static func note(folderPath: String) -> String {
        "フォルダ「\(folderPath)」とその中のファイルは削除されません。"
    }
}

public struct RunningSessionBreakdown: Equatable, Sendable {
    public let visible: Int
    public let nestedOrchestration: Int

    public var total: Int { visible + nestedOrchestration }

    public init(visible: Int, nestedOrchestration: Int) {
        self.visible = visible
        self.nestedOrchestration = nestedOrchestration
    }
}

/// 復元失敗プレースホルダ用の、接続を一切張らないクライアント（`makeRestoreErrorChatSession` 専用）。
/// start/turnStart/resume/interrupt/close はすべて no-op で、`events` は即 finish する空ストリーム。
/// このクライアントを持つ VM は `startNew`/`restore` を呼ばれないためイベントループ・接続を起動しない。
struct DisconnectedStructuredAgentClient: StructuredAgentClient {
    let events: AsyncStream<NormalizedChatEvent>

    init() {
        self.events = AsyncStream { $0.finish() }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}
}

func dashboardSessionStatusIsAwaitingApproval(_ status: SessionStatus) -> Bool {
    if case .awaitingApproval = status {
        true
    } else {
        false
    }
}

public enum AgentSpawnError: Error, Equatable, LocalizedError {
    case binaryNotFound(AgentKind)
    case customBinaryNotFound(String)
    case spawnRateLimited
    case depthLimitExceeded
    case unknownProject
    case noProject
    case unsupportedBackend

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let kind):
            String(localized: "\(kind.displayName) の実行ファイルが見つかりませんでした。PATH を確認してください。")
        case .customBinaryNotFound(let id):
            String(localized: "\(id) の実行ファイルが見つかりませんでした。PATH と agents.json を確認してください。")
        case .spawnRateLimited:
            String(localized: "短時間に作成できるセッション数の上限を超えました。")
        case .depthLimitExceeded:
            String(localized: "セッション作成の深度上限を超えました。")
        case .unknownProject:
            String(localized: "指定されたプロジェクトが見つかりません。")
        case .noProject:
            String(localized: "プロジェクトが登録されていません。サイドバーからフォルダを追加してください。")
        case .unsupportedBackend:
            String(localized: "このセッション backend は指定されたエージェントでは利用できません。")
        }
    }
}

enum WorkspaceSetupError: Error, LocalizedError {
    case hooksSkippedExistingUserFile

    var errorDescription: String? {
        switch self {
        case .hooksSkippedExistingUserFile:
            String(localized: "既存のユーザー設定ファイルがあるため hooks を設置できませんでした。")
        }
    }
}
