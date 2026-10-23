import Foundation
import AgentDomain
import DesignSystem

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
