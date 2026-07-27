import PhloxCore
import SwiftUI

#if os(iOS)
import SwiftTerm
import UIKit
#endif

/// Mac の端末画面（ANSI）を、Mac と同じエンジン（SwiftTerm）で描き直す読み取り専用ビュー。
///
/// 幅は**常に与えられた画面幅に収める**（横スクロールさせない）。Mac の桁数が収まるところまで
/// フォントを縮め、読める下限まで縮めても収まらなければ折り返す。
public struct TerminalScreenView: View {
    private let screen: TerminalScreen
    private let preferredFontSize: CGFloat

    @State private var availableWidth: CGFloat = 0

    public init(screen: TerminalScreen, fontSize: CGFloat = 12) {
        self.screen = screen
        self.preferredFontSize = fontSize
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 高さ0のプローブで「使える幅」を測る。端末自身に測らせると、幅が決まる前に
            // 桁数が決まってしまい折り返しがずれる。
            Color.clear
                .frame(height: 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TerminalScreenWidthKey.self, value: proxy.size.width)
                    }
                )

            if availableWidth > 0 {
                content(width: availableWidth)
            }
        }
        .onPreferenceChange(TerminalScreenWidthKey.self) { width in
            if availableWidth != width { availableWidth = width }
        }
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        #if os(iOS)
        let layout = TerminalScreenLayout(screen: screen, preferredFontSize: preferredFontSize, width: width)
        TerminalScreenRepresentable(screen: screen, layout: layout)
            .frame(width: layout.width, height: layout.height)
        #else
        // ホスト（macOS）ではビルドが通ることだけを保証する。実描画は iOS のみ。
        Text(screen.plainText)
            .font(.footnote.monospaced())
            .frame(width: width, alignment: .leading)
        #endif
    }
}

private struct TerminalScreenWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if os(iOS)
/// 画面幅から確定させたフォントサイズ・桁数・描画サイズ。
private struct TerminalScreenLayout: Equatable {
    let fontSize: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(screen: TerminalScreen, preferredFontSize: CGFloat, width: CGFloat) {
        let macColumns = screen.cols ?? 0
        let fontSize = TerminalScreenMetrics.fittingFontSize(
            columns: macColumns,
            availableWidth: width,
            preferredFontSize: preferredFontSize,
            cellWidthAtPreferredSize: TerminalScreenLayout.cellSize(fontSize: preferredFontSize).width
        )
        let cell = TerminalScreenLayout.cellSize(fontSize: fontSize)
        let columns = TerminalScreenMetrics.columns(availableWidth: width, cellWidth: cell.width)
        let rows = TerminalScreenMetrics.wrappedRowCount(plainText: screen.plainText, columns: columns)
        self.fontSize = fontSize
        self.width = width
        self.height = CGFloat(rows + TerminalScreenMetrics.safetyRows) * cell.height
    }

    /// SwiftTerm の内部セル寸法は非公開なので、同じフォントで同じ式
    /// （`"W"` の advance と ascent+descent+leading の切り上げ）を再現する。
    static func cellSize(fontSize: CGFloat) -> CGSize {
        let uiFont = font(size: fontSize)
        let scale = UITraitCollection.current.displayScale > 0 ? UITraitCollection.current.displayScale : 1
        let width = "W".size(withAttributes: [.font: uiFont]).width
        let ctFont = uiFont as CTFont
        let height = ceil(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
        return CGSize(
            width: ceil(width * scale) / scale,
            height: ceil(height * scale) / scale
        )
    }

    static func font(size: CGFloat) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

private struct TerminalScreenRepresentable: UIViewRepresentable {
    let screen: TerminalScreen
    let layout: TerminalScreenLayout

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(
            frame: CGRect(x: 0, y: 0, width: layout.width, height: layout.height),
            font: TerminalScreenLayout.font(size: layout.fontSize)
        )
        // 読み取り専用。キーボードもカーソルも出さない。
        view.isUserInteractionEnabled = false
        Self.applyPalette(to: view)
        return view
    }

    func updateUIView(_ view: SwiftTerm.TerminalView, context: Context) {
        let size = CGSize(width: layout.width, height: layout.height)
        // SwiftTerm は frame から桁数・行数を決める。feed 前に確定させないと折り返しが変わる。
        if view.font.pointSize != layout.fontSize {
            view.font = TerminalScreenLayout.font(size: layout.fontSize)
        }
        if view.frame.size != size {
            view.frame = CGRect(origin: view.frame.origin, size: size)
            view.layoutIfNeeded()
        }
        let token = Coordinator.Token(text: screen.text, size: size, fontSize: layout.fontSize)
        guard context.coordinator.lastRendered != token else { return }
        context.coordinator.lastRendered = token
        // 直前の画面が残らないよう毎回クリアしてから流す（差分ではなくスナップショットのため）。
        view.getTerminal().resetToInitialState()
        // 読み取り専用なのでカーソルは出さない（DECTCEM off）。
        view.feed(text: "\u{1B}[?25l" + Self.terminalLineEndings(screen.text))
    }

    /// 端末では LF は「1行下へ」でしかなく、桁は戻らない。行頭から描くために CR を補う。
    /// 伝送する本文は `\n` 区切りのまま保つ（行数の判定や本文抽出を単純にしておくため）。
    static func terminalLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        struct Token: Equatable {
            let text: String
            let size: CGSize
            let fontSize: CGFloat
        }

        var lastRendered: Token?
    }

    private static func applyPalette(to view: SwiftTerm.TerminalView) {
        let palette = TerminalScreenPalette.phloxDefault
        view.installColors(palette.ansi.map(swiftTermColor))
        view.nativeBackgroundColor = uiColor(palette.background)
        view.nativeForegroundColor = uiColor(palette.foreground)
        view.backgroundColor = uiColor(palette.background)
    }

    private static func swiftTermColor(_ channel: TerminalScreenPalette.Channel) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16(channel.r) * 257,
            green: UInt16(channel.g) * 257,
            blue: UInt16(channel.b) * 257
        )
    }

    private static func uiColor(_ channel: TerminalScreenPalette.Channel) -> UIColor {
        UIColor(
            red: CGFloat(channel.r) / 255,
            green: CGFloat(channel.g) / 255,
            blue: CGFloat(channel.b) / 255,
            alpha: 1
        )
    }
}
#endif
