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

/// ワークスペース削除確認ダイアログの文言。View 直テストが困難なため純関数として切り出す。
public enum ProjectDeletionDialogText {
    public static func title(descendantCount: Int) -> String {
        if descendantCount > 0 {
            return "このプロジェクトの削除で子孫\(descendantCount)件も削除されますか?"
        }
        return "このプロジェクトを削除しますか?"
    }

    public static func message(descendantCount: Int) -> String {
        if descendantCount > 0 {
            return "配下のセッションはすべて停止されます。この一覧に表示されていない子孫セッション\(descendantCount)件も併せて削除されます。フォルダ自体は削除されません。"
        }
        return "配下のセッションはすべて停止されます。フォルダ自体は削除されません。"
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
