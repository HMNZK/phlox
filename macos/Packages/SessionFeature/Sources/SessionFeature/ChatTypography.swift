import CoreGraphics
import DesignSystem

/// チャット本文系フォントサイズの単一の真実源。
public enum ChatTypography {
    public static func bodyFontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .body, scale: scale)
    }

    public static func codeFontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .inlineCode, scale: scale)
    }

    public static func heading1FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading1, scale: scale)
    }

    public static func heading2FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading2, scale: scale)
    }

    public static func heading3FontSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .heading3, scale: scale)
    }
}
