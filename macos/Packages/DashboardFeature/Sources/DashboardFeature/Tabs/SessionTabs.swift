import Foundation
import Observation
import AgentDomain
import DesignSystem

/// セッションの子タブ（02 C）。会話は常にあり、閉じられない。
public enum ChildTab: Hashable, Codable, Sendable {
    case conversation
    case terminal
    case changes
    /// worktree 直下からの相対パス。
    case file(String)
}

/// 1 セッション分の子タブの並び・選択・左右分割。
public struct SessionTabLayout: Codable, Equatable, Sendable {
    public var tabs: [ChildTab] = [.conversation]
    /// 左（分割なしなら唯一）の区画に出す子タブ。
    public var left: ChildTab = .conversation
    /// 右の区画に出す子タブ。nil なら分割なし。
    public var right: ChildTab?
    /// 分割中に右の区画を操作しているか。
    public var focusesRight = false
    /// 左の区画の幅の割合（既定 50:50）。
    public var splitFraction: Double = 0.5

    public init() {}

    /// 操作中の子タブ。
    public var selected: ChildTab {
        focusesRight ? (right ?? left) : left
    }

    public func isShown(_ tab: ChildTab) -> Bool {
        tab == left || tab == right
    }

    /// 開いていなければ末尾に足し、前に出す。
    public mutating func open(_ tab: ChildTab) {
        if !tabs.contains(tab) { tabs.append(tab) }
        select(tab)
    }

    /// 出ている区画ならそこへ移り、出ていなければ操作中の区画に出す。
    public mutating func select(_ tab: ChildTab) {
        guard tabs.contains(tab) else { return }
        if tab == left {
            focusesRight = false
        } else if tab == right {
            focusesRight = true
        } else if focusesRight, right != nil {
            right = tab
        } else {
            left = tab
        }
    }

    /// 閉じたら true。会話は閉じない。区画に出ていたら左隣（分割中はもう一方）を出す。
    @discardableResult
    public mutating func close(_ tab: ChildTab) -> Bool {
        guard tab != .conversation, let index = tabs.firstIndex(of: tab) else { return false }
        tabs.remove(at: index)
        if right == tab {
            right = nil
            focusesRight = false
        } else if left == tab {
            if let right {
                left = right
                self.right = nil
            } else {
                left = tabs[max(0, index - 1)]
            }
            focusesRight = false
        }
        return true
    }

    /// ⌃Tab / ⌃⇧Tab。端で折り返す。
    public mutating func cycle(by offset: Int) {
        guard let index = tabs.firstIndex(of: selected), tabs.count > 1 else { return }
        let count = tabs.count
        select(tabs[((index + offset) % count + count) % count])
    }

    /// 指定タブを右の区画に出して操作する（⌘\・右端へのドラッグ）。左には別のタブを残す。
    public mutating func splitRight(_ tab: ChildTab) {
        guard tabs.contains(tab) else { return }
        if tab == left {
            guard let other = right ?? tabs.first(where: { $0 != tab }) else { return }
            left = other
        }
        right = tab
        focusesRight = true
    }

    /// ⌘\：分割中なら操作中のタブだけを残して解除、分割なしなら現在のタブを右へ。
    public mutating func toggleSplit() {
        if right != nil {
            left = selected
            right = nil
            focusesRight = false
        } else {
            splitRight(left)
        }
    }
}

/// プロジェクトの上段タブ列。並びと、✕ で閉じたセッション（セッション自体は残る）。
public struct ProjectTabState: Codable, Equatable, Sendable {
    public var order: [SessionID] = []
    public var closed: Set<SessionID> = []

    public init() {}
}

/// 上段タブ列・子タブの保存形。プロジェクトごとの並びと、セッションごとの子タブを持つ。
public struct SessionTabsSnapshot: Codable, Equatable, Sendable {
    public var projects: [ProjectID: ProjectTabState] = [:]
    public var sessions: [SessionID: SessionTabLayout] = [:]

    public init() {}

    /// 上段に出すセッション。保存済みの並び → 新しいセッションの順。閉じたものは除く。
    public func sessionTabs(in projectID: ProjectID, candidates: [SessionID]) -> [SessionID] {
        let state = projects[projectID] ?? ProjectTabState()
        let existing = Set(candidates)
        let saved = state.order.filter { existing.contains($0) }
        let added = candidates.filter { !state.order.contains($0) }
        return (saved + added).filter { !state.closed.contains($0) }
    }

    /// 選んだセッションを上段に出す（閉じていたら開き直す）。
    public mutating func reveal(_ sessionID: SessionID, in projectID: ProjectID, candidates: [SessionID]) {
        var state = projects[projectID] ?? ProjectTabState()
        let visibleBefore = sessionTabs(in: projectID, candidates: candidates)
        state.closed.remove(sessionID)
        if !state.order.contains(sessionID) {
            // 今の見た目の並びを固定する。見えていなかったものは末尾に足す。
            state.order = visibleBefore.contains(sessionID) ? visibleBefore : visibleBefore + [sessionID]
        }
        projects[projectID] = state
    }

    /// 上段のタブを閉じる。閉じた後に選ぶ隣のセッション（無ければ nil）を返す。
    public mutating func closeSessionTab(
        _ sessionID: SessionID,
        in projectID: ProjectID,
        candidates: [SessionID]
    ) -> SessionID? {
        let visible = sessionTabs(in: projectID, candidates: candidates)
        var state = projects[projectID] ?? ProjectTabState()
        if state.order.isEmpty { state.order = visible }
        state.closed.insert(sessionID)
        projects[projectID] = state
        guard let index = visible.firstIndex(of: sessionID) else { return nil }
        let rest = visible.filter { $0 != sessionID }
        guard !rest.isEmpty else { return nil }
        return rest[min(index, rest.count - 1)]
    }

    /// 上段のタブをドラッグで並べ替える。右へ動かすときは落とした先の後ろ、左へは前に入れる。
    public mutating func moveSessionTab(
        _ sessionID: SessionID,
        onto target: SessionID,
        in projectID: ProjectID,
        candidates: [SessionID]
    ) {
        var visible = sessionTabs(in: projectID, candidates: candidates)
        guard sessionID != target,
              let from = visible.firstIndex(of: sessionID),
              let targetIndex = visible.firstIndex(of: target) else { return }
        visible.remove(at: from)
        // 取り除いた後の targetIndex は、右へ動かすなら落とした先の後ろ、左へなら前にあたる。
        visible.insert(sessionID, at: targetIndex)
        var state = projects[projectID] ?? ProjectTabState()
        state.order = visible
        projects[projectID] = state
    }

    /// 削除したセッションの記録を捨てる。
    public mutating func forget(_ sessionID: SessionID) {
        sessions[sessionID] = nil
        for key in projects.keys {
            projects[key]?.order.removeAll { $0 == sessionID }
            projects[key]?.closed.remove(sessionID)
        }
    }

    public mutating func forgetProject(_ projectID: ProjectID) {
        projects[projectID] = nil
    }
}

/// タブがあふれて見えない位置にある対応待ちの要約（C7「隠れたタブに 質問待ち 1」）。
/// 種類が 1 つならその状態名、混在なら「対応待ち」とまとめる。
public struct HiddenAttentionSummary: Equatable, Sendable {
    public let kind: AttentionKind?
    public let count: Int

    public static func make(hiddenStates: [SessionDisplayState]) -> HiddenAttentionSummary? {
        let kinds = hiddenStates.compactMap(\.attentionKind)
        guard let first = kinds.first else { return nil }
        let isSingleKind = kinds.allSatisfy { $0 == first }
        return HiddenAttentionSummary(kind: isSingleKind ? first : nil, count: kinds.count)
    }
}

/// ⌘W の振り分け（13 Review で確定）。
public enum CloseCommandTarget: Equatable, Sendable {
    /// 会話以外の子タブを閉じる。
    case childTab(ChildTab)
    /// 会話タブ・グリッドでは、確認してからセッションを削除する。
    case session(SessionID)
}

/// タブの状態の持ち主。App のメニュー（⌘W・⌘1–9・⌃Tab）と画面の両方から触るので Router に置く。
@MainActor
@Observable
public final class SessionTabStore {
    public private(set) var snapshot: SessionTabsSnapshot

    @ObservationIgnored private let defaults: UserDefaults?
    static let defaultsKey = "phlox.sessionTabs.v1"

    /// defaults が nil なら保存しない（テスト・プレビュー用）。
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SessionTabsSnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = SessionTabsSnapshot()
        }
    }

    public func layout(for sessionID: SessionID) -> SessionTabLayout {
        snapshot.sessions[sessionID] ?? SessionTabLayout()
    }

    public func updateLayout(for sessionID: SessionID, _ change: (inout SessionTabLayout) -> Void) {
        var layout = layout(for: sessionID)
        change(&layout)
        mutate { $0.sessions[sessionID] = layout }
    }

    public func sessionTabs(in projectID: ProjectID, candidates: [SessionID]) -> [SessionID] {
        snapshot.sessionTabs(in: projectID, candidates: candidates)
    }

    public func reveal(_ sessionID: SessionID, in projectID: ProjectID, candidates: [SessionID]) {
        mutate { $0.reveal(sessionID, in: projectID, candidates: candidates) }
    }

    public func closeSessionTab(_ sessionID: SessionID, in projectID: ProjectID, candidates: [SessionID]) -> SessionID? {
        var next: SessionID?
        mutate { next = $0.closeSessionTab(sessionID, in: projectID, candidates: candidates) }
        return next
    }

    public func moveSessionTab(_ sessionID: SessionID, onto target: SessionID, in projectID: ProjectID, candidates: [SessionID]) {
        mutate { $0.moveSessionTab(sessionID, onto: target, in: projectID, candidates: candidates) }
    }

    public func forget(_ sessionID: SessionID) {
        mutate { $0.forget(sessionID) }
    }

    public func forgetProject(_ projectID: ProjectID) {
        mutate { $0.forgetProject(projectID) }
    }

    /// ⌘W の対象。単体表示で会話以外の子タブを選んでいればそのタブ、それ以外はセッション。
    public func closeTarget(selectedSession: SessionID?, viewMode: ViewMode) -> CloseCommandTarget? {
        guard let selectedSession else { return nil }
        if viewMode == .single {
            let selected = layout(for: selectedSession).selected
            if selected != .conversation { return .childTab(selected) }
        }
        return .session(selectedSession)
    }

    private func mutate(_ change: (inout SessionTabsSnapshot) -> Void) {
        var next = snapshot
        change(&next)
        guard next != snapshot else { return }
        snapshot = next
        if let defaults, let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

extension DashboardViewModel {
    /// ⌘1–9 で選ぶ並び。単体では上段のセッションタブ、グリッドではタイル（左上から）。
    public func numberedTabSessionIDs(router: AppRouter) -> [SessionID] {
        switch router.viewMode {
        case .grid:
            return filteredGridSessionNodes(projectID: router.gridFilterProjectID).map(\.id)
        case .single:
            let projectID = router.selectedSession.flatMap { sessionNode(id: $0)?.projectID } ?? router.selectedProjectID
            guard let projectID else { return [] }
            return router.tabs.sessionTabs(in: projectID, candidates: sessionNodes(in: projectID).map(\.id))
        }
    }
}
