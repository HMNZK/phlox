import Foundation

/// 非 Lazy の transcript が描画する末尾件数を管理する純粋な値型。
/// スクロール位置やレイアウト計測には依存せず、展開は明示的なユーザー操作でのみ行う。
struct TranscriptWindow: Equatable {
    static let defaultLimit = 50
    static let expandStep = 50

    private(set) var limit: Int

    init() {
        limit = Self.defaultLimit
    }

    func visibleRange(totalCount: Int) -> (startIndex: Int, hiddenCount: Int) {
        guard totalCount > limit else {
            return (startIndex: 0, hiddenCount: 0)
        }
        let hiddenCount = totalCount - limit
        return (startIndex: hiddenCount, hiddenCount: hiddenCount)
    }

    mutating func expand() {
        if limit <= Int.max - Self.expandStep {
            limit += Self.expandStep
        } else {
            limit = Int.max
        }
    }

    mutating func reset() {
        limit = Self.defaultLimit
    }
}
