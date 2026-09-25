import AppKit

/// ターミナルの文字サイズ設定の単一の真実源。
/// UserDefaults に Double で保存し、App 層と DashboardViewModel の双方が同じキーを参照する。
public enum TerminalFontSettings {
    public static let fontSizeKey = "phlox.terminal.fontSize"

    public static let minSize: CGFloat = 8
    public static let maxSize: CGFloat = 32
    public static let step: CGFloat = 1

    /// 起動時に UserDefaults.register(defaults:) へ渡す既定値。
    public static var defaultsDictionary: [String: Any] {
        [fontSizeKey: Double(NSFont.systemFontSize)]
    }

    public static func currentSize(defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.double(forKey: fontSizeKey)
        // register(defaults:) 未適用の環境では 0 が返るためフォールバック。
        let raw = stored > 0 ? CGFloat(stored) : NSFont.systemFontSize
        return clamped(raw)
    }

    /// グリッドのタイルでは単体表示より一段小さく描く（06: 単体 11.5 に対してタイル 11）。
    /// 表示モードは DashboardViewModel が切り替える。0.5pt 刻みに丸める。
    @MainActor public static var isGridLayout = false

    /// 端末へ実際に当てる大きさ（グリッドなら 11 / 11.5 倍）。
    @MainActor public static func displaySize(_ size: CGFloat) -> CGFloat {
        isGridLayout ? gridSize(size) : size
    }

    /// グリッドのタイルでの大きさ。
    public static func gridSize(_ size: CGFloat) -> CGFloat {
        max(minSize, (size * 11 / 11.5 * 2).rounded() / 2)
    }

    public static func save(_ size: CGFloat, defaults: UserDefaults = .standard) {
        defaults.set(Double(size), forKey: fontSizeKey)
    }

    /// delta を加算してクランプした新サイズを返す。永続化は呼び出し元の責務。
    public static func adjusted(from current: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(current + delta)
    }

    /// 設定画面の入力欄（10 Settings T6b）。範囲内の整数だけを受け付け、それ以外は nil（保存しない）。
    public static func parse(_ text: String) -> CGFloat? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              CGFloat(value) >= minSize, CGFloat(value) <= maxSize
        else { return nil }
        return CGFloat(value)
    }

    private static func clamped(_ size: CGFloat) -> CGFloat {
        min(maxSize, max(minSize, size))
    }
}
