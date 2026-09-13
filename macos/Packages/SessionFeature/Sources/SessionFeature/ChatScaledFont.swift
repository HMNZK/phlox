import SwiftUI
import DesignSystem

/// セル本文・コードブロック chrome 用のスケール追従フォント。
/// 正本は `TranscriptTypography`。既存 API 名は残し、サイズ・倍率計算の別正本は持たない。
enum ChatScaledFont {
    static func body(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .body, scale: scale)
    }

    /// `body(scale:)` の実寸。Core Animation 経路（CATextLayer）へ渡すために公開する。
    static func bodyPointSize(scale: CGFloat) -> CGFloat {
        TranscriptTypography.pointSize(for: .body, scale: scale)
    }

    static func caption(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .metadata, scale: scale)
    }

    static func captionStrong(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .metadataStrong, scale: scale)
    }

    static func mono(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .code, scale: scale)
    }

    static func monoCaption(scale: CGFloat) -> Font {
        TranscriptTypography.font(for: .codeMetadata, scale: scale)
    }
}
