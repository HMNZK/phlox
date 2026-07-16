import SwiftUI
import PhloxCore

/// セッション一覧（カンプ② / E4-3）。`SessionRepository` を購読し `SessionsState` を反映する。
/// ViewModel は `PhloxAPI` を直接呼ばず Repository 経由のみ。scenePhase 連動で start/stop する。
@MainActor
@Observable
public final class SessionListViewModel {
    /// UI テスト・スクリーンショット用の既定ホスト（接続設定未保存時の表示フォールバック）。
    public static let uiTestFallbackHost = "100.64.0.1"

    /// 「実行中・その他」セクション見出し（カンプ②）。
    public static let otherSectionTitle = "実行中・その他"

    private let repository: SessionRepositoryProtocol
    private let configStore: ConnectionConfigStoring
    public private(set) var state: SessionsState = .loading
    public private(set) var lastFetchedAt: Date?
    /// 直近に取得できたセッション群。`.loading`/`.offline`/`.error` 等の一時的な非 loaded 状態でも
    /// ナビゲーション先（詳細）が消えないよう、id 解決のフォールバックに使う。
    public private(set) var lastKnownSessions: [Session] = []
    private var task: Task<Void, Never>?

    public init(
        repository: SessionRepositoryProtocol,
        configStore: ConnectionConfigStoring = UserDefaultsConnectionConfigStore()
    ) {
        self.repository = repository
        self.configStore = configStore
    }

    /// 接続先ホスト（設定未保存時は UI テスト用フォールバック）。
    public var connectionHost: String {
        let stored = configStore.load()?.host.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? Self.uiTestFallbackHost : stored
    }

    /// loaded 状態のセッション件数。
    public var sessionCount: Int {
        allSessions.count
    }

    /// ナビ直下のメタ行（`5 件 · 100.64.0.1`）。
    public var listSubtitle: String {
        Self.listSubtitle(sessionCount: sessionCount, host: connectionHost)
    }

    /// 「あなたの番 · N」見出し。
    public var attentionSectionTitle: String {
        Self.attentionSectionTitle(count: attentionSessions.count)
    }

    /// カンプ②の件数・ホスト行を組み立てる（テスト可能な決定点）。
    public nonisolated static func listSubtitle(sessionCount: Int, host: String) -> String {
        "\(sessionCount) 件 · \(host)"
    }

    /// カンプ②の attention セクション見出しを組み立てる。
    public nonisolated static func attentionSectionTitle(count: Int) -> String {
        "あなたの番 · \(count)"
    }

    /// 「あなたの番」（承認待ち）セッション。
    public var attentionSessions: [Session] {
        guard case .loaded(let sessions) = state else { return [] }
        return sessions.filter(\.needsAttention)
    }

    /// 全セッション（loaded のときのみ）。
    public var allSessions: [Session] {
        guard case .loaded(let sessions) = state else { return [] }
        return sessions
    }

    /// id でセッションを解決する。現在 loaded ならそこから、非 loaded（再購読中の loading/offline 等）
    /// なら直近取得分から返す。バックグラウンド復帰時に詳細画面が「見つかりません」へ転落するのを防ぐ。
    public func session(id: String) -> Session? {
        allSessions.first { $0.id == id } ?? lastKnownSessions.first { $0.id == id }
    }

    /// 「実行中・その他」— あなたの番（needsAttention）を除く。
    public var otherSessions: [Session] {
        guard case .loaded(let sessions) = state else { return [] }
        return sessions.filter { !$0.needsAttention }
    }

    /// loaded 状態の全セッションをプロジェクト単位にグルーピングした結果。
    public var projectGroups: [ProjectGroup] {
        SessionGrouping.grouped(from: allSessions)
    }

    /// DisclosureGroup 表示用（あなたの番を除きプロジェクト単位にグルーピング）。
    public var groupedOtherSessions: [ProjectGroup] {
        SessionGrouping.grouped(from: otherSessions)
    }

    /// ストリームを購読し続ける（テストは直接 await して終了を待てる）。
    public func observe(interval: Duration = .seconds(3)) async {
        for await next in repository.sessionStream(interval: interval) {
            if case .loaded(let sessions) = next {
                lastFetchedAt = Date()
                lastKnownSessions = sessions
            }
            state = next
        }
    }

    /// View 用: バックグラウンド Task で購読開始（scenePhase .active で呼ぶ）。
    public func start(interval: Duration = .seconds(3)) {
        task?.cancel()
        task = Task { [weak self] in
            await self?.observe(interval: interval)
        }
    }

    /// scenePhase .background で呼ぶ。ポーリング停止。
    public func stop() {
        task?.cancel()
        task = nil
    }

    public func refresh() async {
        try? await repository.refresh()
    }

    /// UI テスト / スクリーンショット用に一覧状態を直接固定する（`-UITesting` 時のみ）。
    public func seedStateForUITesting(_ state: SessionsState) {
        guard ProcessInfo.processInfo.arguments.contains("-UITesting") else { return }
        self.state = state
        if case .loaded = state {
            lastFetchedAt = Date()
        }
        if case .offline = state {
            lastFetchedAt = Date().addingTimeInterval(-180)
        }
    }
}
