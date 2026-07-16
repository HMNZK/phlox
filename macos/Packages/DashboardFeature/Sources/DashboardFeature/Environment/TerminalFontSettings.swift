import AppKit

/// ターミナルの文字サイズ設定の単一の真実源。
/// UserDefaults に Double で保存し、App 層と DashboardViewModel の双方が同じキーを参照する。
public enum TerminalFontSettings {
    public static let fontSizeKey = "phlox.terminal.fontSize"

    public static let minSize: CGFloat = 9
    public static let maxSize: CGFloat = 24
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

    public static func save(_ size: CGFloat, defaults: UserDefaults = .standard) {
        defaults.set(Double(size), forKey: fontSizeKey)
    }

    /// delta を加算してクランプした新サイズを返す。永続化は呼び出し元の責務。
    public static func adjusted(from current: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(current + delta)
    }

    private static func clamped(_ size: CGFloat) -> CGFloat {
        min(maxSize, max(minSize, size))
    }
}
