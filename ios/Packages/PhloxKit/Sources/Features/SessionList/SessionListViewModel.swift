import SwiftUI
import PhloxCore

/// セッション一覧の取得状態と、一覧表示に必要な API の補助データを持つ。
@MainActor
@Observable
public final class SessionListViewModel {
    /// UI テスト・スクリーンショット用の既定ホスト（接続設定未保存時の表示フォールバック）。
    public static let uiTestFallbackHost = "100.64.0.1"

    private let repository: SessionRepositoryProtocol
    private let api: (any PhloxAPI)?
    private let configStore: ConnectionConfigStoring
    public private(set) var state: SessionsState = .loading
    public private(set) var lastFetchedAt: Date?
    public private(set) var projectOrder: [ProjectSummary]?
    public private(set) var projectOrderError: PhloxError?
    /// 直近に取得できたセッション群。`.loading`/`.offline`/`.error` 等の一時的な非 loaded 状態でも
    /// ナビゲーション先（詳細）が消えないよう、id 解決のフォールバックに使う。
    public private(set) var lastKnownSessions: [Session] = []
    private var task: Task<Void, Never>?
    private var hasRequestedProjectOrder = false

    public init(
        repository: SessionRepositoryProtocol,
        api: (any PhloxAPI)? = nil,
        configStore: ConnectionConfigStoring = UserDefaultsConnectionConfigStore()
    ) {
        self.repository = repository
        self.api = api
        self.configStore = configStore
    }

    /// 接続先ホスト（設定未保存時は UI テスト用フォールバック）。
    public var connectionHost: String {
        let stored = configStore.load()?.host.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? Self.uiTestFallbackHost : stored
    }

    public var connectionEndpoint: String {
        let config = configStore.load()
        let host = config?.host.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedHost = host.isEmpty ? Self.uiTestFallbackHost : host
        return "\(resolvedHost):\(config?.port ?? 8765)"
    }

    public var projection: SessionListProjection {
        SessionListProjection.make(sessions: allSessions, projects: projectOrder)
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

    /// ストリームを購読し続ける（テストは直接 await して終了を待てる）。
    public func observe(interval: Duration = .seconds(3)) async {
        for await next in repository.sessionStream(interval: interval) {
            if case .loaded(let sessions) = next {
                lastFetchedAt = Date()
                lastKnownSessions = sessions
            }
            if case .empty = next {
                lastFetchedAt = Date()
                lastKnownSessions = []
            }
            state = next
            if case .loaded = next, !hasRequestedProjectOrder, api != nil {
                hasRequestedProjectOrder = true
                await refreshProjectOrder()
            }
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
        do {
            try await repository.refresh()
        } catch let error as PhloxError {
            state = .error(error)
        } catch {
            state = .error(.transport(WrappedError(error)))
        }
        await refreshProjectOrder()
    }

    private func refreshProjectOrder() async {
        guard let api else { return }
        do {
            projectOrder = try await api.projects()
            projectOrderError = nil
        } catch let error as PhloxError {
            projectOrder = nil
            projectOrderError = error
        } catch {
            projectOrder = nil
            projectOrderError = .transport(WrappedError(error))
        }
    }

    /// UI テスト / スクリーンショット用に一覧状態を直接固定する（`-UITesting` 時のみ）。
    public func seedStateForUITesting(_ state: SessionsState) {
        let variables = ProcessInfo.processInfo.environment
        guard ProcessInfo.processInfo.arguments.contains("-UITesting")
                || variables["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        self.state = state
        if case .loaded = state {
            lastFetchedAt = Date()
        }
        if case .offline = state {
            lastFetchedAt = Date().addingTimeInterval(-180)
        }
    }
}
