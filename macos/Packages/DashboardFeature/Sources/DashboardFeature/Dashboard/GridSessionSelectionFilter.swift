import Foundation

// task-14 契約の PM スタブ。API 表面は受け入れテスト
// GridSessionSelectionAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-14.md

/// グリッドに表示するセッションの選択フィルタ（nil = 全表示）。
enum GridSessionSelectionFilter {
    /// selection が nil なら items をそのまま返す。非 nil なら selection に含まれる要素のみ。
    static func apply<T: Identifiable>(_ items: [T], selection: Set<T.ID>?) -> [T] {
        guard let selection else { return items }
        return items.filter { selection.contains($0.id) }
    }

    /// selection の正規化: 存在しない ID を掃除し、空になったら nil（=全表示）へ戻す。
    static func normalized<ID: Hashable>(selection: Set<ID>?, existing: Set<ID>) -> Set<ID>? {
        guard let selection else { return nil }
        let pruned = selection.intersection(existing)
        return pruned.isEmpty ? nil : pruned
    }
}
