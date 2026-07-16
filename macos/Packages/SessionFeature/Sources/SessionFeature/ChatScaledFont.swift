import SwiftUI

/// セル本文・コードブロック chrome 用のスケール追従フォント。
/// 基準サイズは置換元 DSFont の現行実サイズ（macOS 解決値）を保持し、scale 1.0 で
/// 現状の見た目と一致させる（body/mono=13, caption/captionStrong/monoCaption=10）。
/// markdown 本文テーマ（15/13.5/見出し）とは別系統で、ChatTypography には委譲しない。
enum ChatScaledFont {
    /// DSFont.body 相当（Font.body=13pt）。
    static func body(scale: CGFloat) -> Font {
        .system(size: 13 * scale)
    }

    /// DSFont.caption 相当（Font.caption=10pt）。
    static func caption(scale: CGFloat) -> Font {
        .system(size: 10 * scale)
    }

    static func captionStrong(scale: CGFloat) -> Font {
        caption(scale: scale).weight(.medium)
    }

    /// DSFont.mono 相当（Font.system(.body, .monospaced)=13pt）。
    static func mono(scale: CGFloat) -> Font {
        .system(size: 13 * scale, design: .monospaced)
    }

    /// DSFont.monoCaption 相当（Font.system(.caption, .monospaced)=10pt）。
    static func monoCaption(scale: CGFloat) -> Font {
        .system(size: 10 * scale, design: .monospaced)
    }
}
