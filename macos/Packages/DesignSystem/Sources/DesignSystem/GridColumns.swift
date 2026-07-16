import Foundation

/// グリッド表示の列数モード。`auto` は ⌈√N⌉、固定列は 1〜4。
///
/// セッショングリッドのレイアウト設定（`storageKey` で UserDefaults に永続化）。
/// SessionFeature（グリッド描画）と DashboardFeature（ツールバーセレクタ）の双方が
/// 参照する共有の表示設定のため、下層の DesignSystem に置く。
public enum GridColumns: String, CaseIterable, Sendable {
    case auto
    case one
    case two
    case three
    case four

    public static let storageKey = "phlox.grid.columns"

    /// 固定列数。`auto` のときは `nil`。
    public var fixedCount: Int? {
        switch self {
        case .auto: nil
        case .one: 1
        case .two: 2
        case .three: 3
        case .four: 4
        }
    }

    /// ツールバーセレクタ用の短い表示ラベル。
    public var selectorLabel: String {
        switch self {
        case .auto: "Auto"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        }
    }
}
