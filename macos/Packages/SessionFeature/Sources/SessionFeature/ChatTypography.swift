import CoreGraphics

/// チャット本文系フォントサイズの単一の真実源。
public enum ChatTypography {
    public static func bodyFontSize(scale: CGFloat) -> CGFloat {
        15 * scale
    }

    public static func codeFontSize(scale: CGFloat) -> CGFloat {
        13.5 * scale
    }

    public static func heading1FontSize(scale: CGFloat) -> CGFloat {
        26 * scale
    }

    public static func heading2FontSize(scale: CGFloat) -> CGFloat {
        19 * scale
    }

    public static func heading3FontSize(scale: CGFloat) -> CGFloat {
        16 * scale
    }
}
