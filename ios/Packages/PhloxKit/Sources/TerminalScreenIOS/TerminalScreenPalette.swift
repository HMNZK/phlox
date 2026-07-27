import CoreGraphics
import Foundation

/// 端末の配色。Mac の `TerminalUI.TerminalPalette.phloxDefault` と同じ値を持つ。
///
/// Mac が配信するのは「どの ANSI 色か」であって RGB ではないので、同じ画面を同じ色で
/// 見せるには両者が同じパレットを持つ必要がある。`TerminalUI` は macOS 専用（AppKit 依存）で
/// iOS から import できないため、値をここに複製している。**片方だけ変えると色がずれる。**
public struct TerminalScreenPalette: Sendable, Equatable {
    public struct Channel: Sendable, Equatable {
        public let r: Int
        public let g: Int
        public let b: Int

        public init(_ r: Int, _ g: Int, _ b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public let background: Channel
    public let foreground: Channel
    /// ANSI 16 色。
    public let ansi: [Channel]

    public init(background: Channel, foreground: Channel, ansi: [Channel]) {
        self.background = background
        self.foreground = foreground
        self.ansi = ansi
    }

    /// Mac 側 `TerminalPalette.phloxDefault` の複製。
    public static let phloxDefault = TerminalScreenPalette(
        background: Channel(14, 11, 23),
        foreground: Channel(214, 214, 214),
        ansi: [
            Channel(13, 11, 20), Channel(236, 72, 153), Channel(52, 211, 153), Channel(251, 191, 36),
            Channel(124, 140, 255), Channel(168, 85, 247), Channel(56, 189, 248), Channel(236, 233, 245),
            Channel(42, 36, 64), Channel(244, 114, 182), Channel(110, 231, 183), Channel(253, 230, 138),
            Channel(165, 180, 252), Channel(192, 132, 252), Channel(125, 211, 252), Channel(255, 255, 255),
        ]
    )
}
