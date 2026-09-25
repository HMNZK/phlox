import Foundation
import AgentDomain
import DesignSystem
import SessionFeature

/// サイドバーでキー操作の対象になる行（03「キーボード」）。
enum SidebarItem: Hashable {
    case project(ProjectID)
    case session(SessionID)
}

/// ↑↓ と文字入力の頭出し。並びは画面に見えている行の順。
enum SidebarNavigation {
    /// 1 つ隣の行。端では止まる。未選択なら ↓ で先頭、↑ で末尾。
    static func step(from current: SidebarItem?, by offset: Int, in items: [SidebarItem]) -> SidebarItem? {
        guard !items.isEmpty else { return nil }
        guard let current, let index = items.firstIndex(of: current) else {
            return offset > 0 ? items.first : items.last
        }
        return items[min(max(index + offset, 0), items.count - 1)]
    }

    /// 名前が `prefix` で始まる行（大文字小文字を区別しない）。今の行から下へ探し、末尾で先頭へ戻る。
    static func typeSelect(
        _ prefix: String,
        from current: SidebarItem?,
        in items: [(item: SidebarItem, name: String)]
    ) -> SidebarItem? {
        guard !prefix.isEmpty, !items.isEmpty else { return nil }
        let start = current.flatMap { current in items.firstIndex { $0.item == current } } ?? 0
        let ordered = items[start...] + items[..<start]
        return ordered.first { $0.name.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil }?.item
    }
}

/// 畳んだ行に出す中身の要約（03 S5・S6）。状態は記号でなく文字で出す（一覧の状態は文字）。
struct SidebarCollapsedSummary: Equatable {
    struct Entry: Equatable {
        let kind: AttentionKind
        let count: Int
    }

    /// 対応待ちの種類ごとの件数。承認待ち・質問待ち・エラー・無応答の順。
    let attention: [Entry]
    /// 完了の未読の件数。
    let unread: Int

    var isEmpty: Bool { attention.isEmpty && unread == 0 }

    static func make(_ states: [SessionDisplayState]) -> SidebarCollapsedSummary {
        let attention = AttentionKind.allCases.compactMap { kind -> Entry? in
            let count = states.filter { $0.attentionKind == kind }.count
            return count > 0 ? Entry(kind: kind, count: count) : nil
        }
        return SidebarCollapsedSummary(attention: attention, unread: states.filter { $0 == .doneUnread }.count)
    }
}

/// 行の右端に何を出すか（03 行の規則・S1・S4・S5）。
enum SidebarRowMeta {
    struct ProjectTrailing: Equatable {
        /// 畳んだ行の中身の要約（対応待ち・未読）。
        let showsSummary: Bool
        /// 「n 実行中」。
        let showsRunning: Bool
        /// 実行中が無い畳んだ行の件数。
        let showsCount: Bool
    }

    static func project(isExpanded: Bool, summary: SidebarCollapsedSummary, runningCount: Int) -> ProjectTrailing {
        ProjectTrailing(
            showsSummary: !isExpanded && !summary.isEmpty,
            showsRunning: runningCount > 0,
            showsCount: !isExpanded && runningCount == 0
        )
    }

    enum SessionTrailing: Equatable {
        /// 経過時間（1 分ごとに更新）。
        case elapsed
        /// 状態の文言（対応待ちは状態色）。
        case state
    }

    /// 待機は経過時間、それ以外（実行中・完了・対応待ちなど）は状態の文言。
    static func session(_ state: SessionDisplayState) -> SessionTrailing {
        state == .idle ? .elapsed : .state
    }
}

/// サイドバーのセッション一覧の 1 行。オーケストレーションの内部セッションは親ごとに 1 行へまとめる
/// （PhloxSidebar の「内部セッション（オーケストレーション）」・03 G3 案 B）。
enum SidebarTreeLine: Identifiable, Equatable {
    /// `depthOffset` はまとめ行を開いたときに中の行を 1 段下げる分。
    case session(SessionTreeViewModel.Row, depthOffset: Int)
    case internalSessions(parent: SessionID, depth: Int, count: Int, isExpanded: Bool)

    var id: String {
        switch self {
        case .session(let row, _): "session-\(row.id.rawValue)"
        case .internalSessions(let parent, _, _, _): "internal-\(parent.rawValue)"
        }
    }

    /// 見本どおり、内部セッションのまとめ行は親の子の末尾に置く。
    /// `isExpanded` は子を開いたセッション、`expandedParents` はまとめ行を開いた親。
    static func make(
        _ forest: [SessionTreeNode],
        isExpanded: (SessionID) -> Bool,
        expandedParents: Set<SessionID>,
        depthOffset: Int = 0
    ) -> [SidebarTreeLine] {
        forest.flatMap { node -> [SidebarTreeLine] in
            let expanded = isExpanded(node.id)
            var lines: [SidebarTreeLine] = [.session(SessionTreeViewModel.Row(node: node, isExpanded: expanded), depthOffset: depthOffset)]
            guard expanded else { return lines }
            let internalChildren = node.children.filter { $0.launchContext == .orchestration }
            lines += make(node.children.filter { $0.launchContext != .orchestration }, isExpanded: isExpanded, expandedParents: expandedParents, depthOffset: depthOffset)
            guard !internalChildren.isEmpty else { return lines }
            let groupExpanded = expandedParents.contains(node.id)
            lines.append(.internalSessions(parent: node.id, depth: node.depth + 1 + depthOffset, count: internalChildren.count, isExpanded: groupExpanded))
            if groupExpanded {
                lines += make(internalChildren, isExpanded: isExpanded, expandedParents: expandedParents, depthOffset: depthOffset + 1)
            }
            return lines
        }
    }
}

/// 同じ親の中での並べ替え（03 F10）。`reorderSession`（2 つの入れ替え）を隣どうしで繰り返して動かす。
enum SidebarReorder {
    /// `moving` を兄弟の並び `siblings` の `destination` 番目（元の並びでの挿入位置 0...count）へ動かすとき、
    /// 順に入れ替える相手。動かない・兄弟でないときは空。
    static func swapPartners(moving: SessionID, to destination: Int, in siblings: [SessionID]) -> [SessionID] {
        guard let from = siblings.firstIndex(of: moving), (0...siblings.count).contains(destination) else { return [] }
        if destination > from + 1 { return Array(siblings[(from + 1)..<destination]) }
        if destination < from { return Array(siblings[destination..<from].reversed()) }
        return []
    }
}

/// ドラッグ中の挿入位置。`before` なら行の上、そうでなければ下に線を出す。
struct SidebarDropTarget: Equatable {
    let sessionID: SessionID
    let before: Bool
}
