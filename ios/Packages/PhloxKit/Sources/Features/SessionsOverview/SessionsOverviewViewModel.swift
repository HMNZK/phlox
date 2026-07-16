import Foundation
import PhloxCore

/// セッション俯瞰（グリッド / シングル切替）の状態。`sessionStream` 購読は任意の追加初期化子で行う。
@MainActor
@Observable
public final class SessionsOverviewViewModel {
    private var sessions: [Session]
    private var selectedSessionID: String?

    public private(set) var mode: OverviewMode = .grid

    private let repository: SessionRepositoryProtocol?
    private var task: Task<Void, Never>?

    /// 純粋な初期化子。Repository 抜きでセッション配列を直接渡せる（受け入れテスト契約）。
    public init(sessions: [Session]) {
        self.sessions = sessions
        self.selectedSessionID = sessions.first?.id
        self.repository = nil
    }

    /// task-7 ホスト用: `SessionRepository` を購読しセッション一覧を反映する。
    public init(repository: SessionRepositoryProtocol) {
        self.sessions = []
        self.selectedSessionID = nil
        self.repository = repository
    }

    /// グリッド表示対象（全件）。
    public var gridSessions: [Session] {
        sessions
    }

    /// シングル表示対象（選択中 1 件。未選択時は先頭）。
    public var singleSession: Session? {
        guard !sessions.isEmpty else { return nil }
        if let selectedSessionID,
           let selected = sessions.first(where: { $0.id == selectedSessionID }) {
            return selected
        }
        return sessions.first
    }

    /// セッション 0 件かどうか。
    public var isEmpty: Bool {
        sessions.isEmpty
    }

    /// grid ↔ single を反転する。
    public func toggleMode() {
        mode = mode == .grid ? .single : .grid
    }

    /// シングル表示の対象セッションを明示的に選択する。
    public func selectSession(id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id
    }

    /// ストリームを購読し続ける（テストは直接 await して終了を待てる）。
    public func observe(interval: Duration = .seconds(3)) async {
        guard let repository else { return }
        for await next in repository.sessionStream(interval: interval) {
            applyLoadedSessions(from: next)
        }
    }

    /// View 用: バックグラウンド Task で購読開始。
    public func start(interval: Duration = .seconds(3)) {
        guard repository != nil else { return }
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
        guard let repository else { return }
        try? await repository.refresh()
    }

    private func applyLoadedSessions(from state: SessionsState) {
        guard case .loaded(let loaded) = state else { return }
        sessions = loaded
        if let selectedSessionID,
           loaded.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        self.selectedSessionID = loaded.first?.id
    }
}
