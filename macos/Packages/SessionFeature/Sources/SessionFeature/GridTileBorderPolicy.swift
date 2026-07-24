import Foundation

/// グリッドタイルの枠表示の純ポリシー（tasks/task-5.md 契約。受け入れテスト
/// AcceptanceGridSelectionFocusTests が凍結）。
///
/// スケルトン（フェーズ1 凍結公開面）: 現行挙動（requiresAttention が選択枠を完全に
/// 覆い隠す）を写しただけの仮実装。task-5 が「注意喚起と選択の同時視認」を実装し、
/// SessionGridView をこのポリシー経由に配線する。
struct GridTileBorderAppearance: Equatable {
    /// 注意喚起（未確認の停止・承認/質問待ち）の強調表示を出すか。
    var showsAttention: Bool
    /// フォーカス（選択中）の強調表示を出すか。
    var showsFocusHighlight: Bool
}

enum GridTileBorderPolicy {
    static func appearance(
        isFocused: Bool,
        requiresAttention: Bool,
        isDropTargeted: Bool
    ) -> GridTileBorderAppearance {
        GridTileBorderAppearance(
            showsAttention: requiresAttention,
            showsFocusHighlight: isFocused
        )
    }
}
