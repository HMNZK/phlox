import Foundation
import DesignSystem

/// グリッド表示の列・行数をセッション数と列数モードから決定する純関数。
public func sessionGridDimensions(
    columns: GridColumns,
    sessionCount n: Int
) -> (cols: Int, rows: Int) {
    if let fixed = columns.fixedCount {
        let size = max(1, fixed)
        return (size, size)
    }

    guard n > 0 else { return (1, 1) }

    let cols = max(1, Int((Double(n)).squareRoot().rounded(.up)))
    let rows = max(1, Int((Double(n) / Double(cols)).rounded(.up)))
    return (cols, rows)
}
