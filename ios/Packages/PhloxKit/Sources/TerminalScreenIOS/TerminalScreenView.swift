import DesignSystem
import PhloxCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Mac の端末画面（SGR 付きテキスト）を、Mac と同じ配色でそのまま描く読み取り専用ビュー。
///
/// **端末エミュレータは使わない**。受け取る画面はカーソル移動も画面消去も含まない
/// 「SGR ＋ 本文 ＋ 改行」なので、装飾付きテキストとして描けば足りる。エミュレータを挟むと
/// 固定行数の格子に嵌めることになり、格子より中身が高いと先頭が黙ってスクロールバックへ消える
/// （→ ADR 0039）。ただのテキストなら高さは中身が決め、読み切れない分は親のスクロールで読める。
///
/// 幅は**Mac の桁数をそのまま守る**。まずフォントを縮めて画面幅へ収めにいき、読める下限まで
/// 縮めても収まらない分は横スクロールで読む（→ ADR 0040）。折り返すと表・枠線の桁が崩れて
/// デスクトップと別物になるため、折り返しはしない。
public struct TerminalScreenView: View {
    private let screen: TerminalScreen
    private let preferredFontSize: CGFloat
    private let minimumHeight: CGFloat
    private let palette = TerminalScreenPalette.phloxDefault

    @State private var availableWidth: CGFloat = 0
    /// 組み立て済みの行。字送りの計算まで済ませてあるので、描画のたびに組み直さない。
    @State private var lines: [AttributedString] = []

    /// - Parameter minimumHeight: 中身がこれより低くても端末の地をここまで伸ばす。
    ///   「画面の下半分だけ地の色が違う」状態を避けるためで、中身の高さは縛らない。
    public init(screen: TerminalScreen, fontSize: CGFloat = 12, minimumHeight: CGFloat = 0) {
        self.screen = screen
        self.preferredFontSize = fontSize
        self.minimumHeight = minimumHeight
    }

    public var body: some View {
        let fontSize = fittedFontSize
        VStack(alignment: .leading, spacing: 0) {
            // 高さ0のプローブで「使える幅」を測る。本文に測らせるとフォントサイズが決まる前に
            // レイアウトが確定してしまい、詰めたサイズが反映されない。
            Color.clear
                .frame(height: 0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: TerminalScreenWidthKey.self, value: proxy.size.width)
                    }
                )

            // 収まらない桁は折り返さず横スクロールで読む。折り返すと表・枠線が桁ごとずれて
            // デスクトップと別物になる（→ ADR 0040）。
            ScrollView(.horizontal, showsIndicators: false) {
                // 履歴（スクロールバック）ごと受け取るので行数は数百〜数千になりうる。1つの Text へ
                // 組むと画面外まで毎回レイアウトすることになるため、行ごとに遅延描画する。
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(lines[index])
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(Self.color(palette.foreground))
                            .textSelection(.enabled)
                            // 折り返さず、中身が要求する幅と高さをそのまま使う。
                            // 高さを固定すると先頭が切れ、幅を縛ると桁が崩れる。
                            .fixedSize()
                    }
                }
                // 桁数ぶんの幅で固定する。行ごとの実測に任せると、遅延描画で新しい行が出るたびに
                // 中身の幅が変わって横スクロールの位置が飛ぶ。
                .frame(width: contentWidth(fontSize: fontSize), alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.s)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(Self.color(palette.background))
        .onPreferenceChange(TerminalScreenWidthKey.self) { width in
            if availableWidth != width { availableWidth = width }
        }
        // 組み立ては画面かフォントサイズが変わったときだけ。body のたびに数千行を組み直すと
        // 描画が詰まる（字送りの計算が文字数ぶん走るのでなおさら）。
        .onChange(of: screen.text, initial: true) { _, _ in rebuildLines(fontSize: fontSize) }
        .onChange(of: fontSize) { _, newSize in rebuildLines(fontSize: newSize) }
    }

    private func rebuildLines(fontSize: CGFloat) {
        guard fontSize > 0 else { return }
        let cellWidth = Self.cellWidth(fontSize: fontSize)
        lines = AnsiTextParser.lines(of: screen.text, palette: palette).map {
            attributed(line: $0, fontSize: fontSize, cellWidth: cellWidth)
        }
    }

    /// Mac の桁数ぶんの幅。画面幅より狭いときは画面幅まで伸ばして地の色を埋める。
    private func contentWidth(fontSize: CGFloat) -> CGFloat {
        let columns = CGFloat(max(0, screen.cols ?? 0))
        return max(columns * Self.cellWidth(fontSize: fontSize), availableWidth)
    }

    /// Mac の桁数が収まるサイズ。収まらないときは下限で止める（＝その分は横スクロールで読む）。
    private var fittedFontSize: CGFloat {
        TerminalScreenMetrics.fittingFontSize(
            columns: screen.cols ?? 0,
            availableWidth: availableWidth,
            preferredFontSize: preferredFontSize,
            cellWidthAtPreferredSize: Self.cellWidth(fontSize: preferredFontSize)
        )
    }

    private func attributed(
        line: AnsiTextParser.Line,
        fontSize: CGFloat,
        cellWidth: CGFloat
    ) -> AttributedString {
        // 空行も1行ぶんの高さを占めさせる。空文字だと高さ0になり、端末の行間が詰まって見える。
        guard !line.isEmpty else { return AttributedString(" ") }
        var result = AttributedString()
        for run in line {
            result.append(attributed(run: run, fontSize: fontSize, cellWidth: cellWidth))
        }
        return result
    }

    /// 1つの装飾の塊を、桁位置に揃えた `AttributedString` にする。
    ///
    /// 描き方が同じ文字はまとめて 1 つの塊にする（文字ごとに分けると数万個の塊ができる）。
    private func attributed(run: AnsiRun, fontSize: CGFloat, cellWidth: CGFloat) -> AttributedString {
        var result = AttributedString()
        var pending = ""
        var pendingLayout: TerminalCellMetrics.Layout?

        func flush() {
            guard !pending.isEmpty, let pendingLayout else { return }
            var piece = styled(
                AttributedString(pending),
                with: run.style,
                fontSize: fontSize * pendingLayout.scale,
                forcesFont: pendingLayout.scale != 1
            )
            piece.kern = pendingLayout.kerning
            result.append(piece)
            pending = ""
        }

        for character in run.text {
            let layout = TerminalCellMetrics.layout(
                of: character,
                fontSize: fontSize,
                cellWidth: cellWidth
            )
            if pendingLayout != layout {
                flush()
                pendingLayout = layout
            }
            pending.append(character)
        }
        flush()
        return result
    }

    private func styled(
        _ piece: AttributedString,
        with style: AnsiStyle,
        fontSize: CGFloat,
        forcesFont: Bool
    ) -> AttributedString {
        var piece = piece
        // 反転は前景と背景を入れ替える。省略されている側は端末の既定色が入る。
        let foreground = style.isInverse
            ? (style.background ?? palette.background)
            : (style.foreground ?? palette.foreground)
        let background = style.isInverse
            ? (style.foreground ?? palette.foreground)
            : style.background

        piece.foregroundColor = Self.color(foreground).opacity(style.isDim ? Self.dimOpacity : 1)
        if let background {
            piece.backgroundColor = Self.color(background)
        }
        if style.isBold || style.isItalic || forcesFont {
            var font = Font.system(size: fontSize, weight: style.isBold ? .bold : .regular, design: .monospaced)
            if style.isItalic { font = font.italic() }
            piece.font = font
        }
        if style.isUnderlined { piece.underlineStyle = .single }
        if style.isStruckThrough { piece.strikethroughStyle = .single }
        return piece
    }

    /// 端末の地の色。端末を全面に出す画面が、端末より下の余白まで同じ色で塗るために使う。
    /// 塗らないと「画面の上半分だけ端末で、下半分は別の色」に見える。
    public static var backgroundColor: Color { color(TerminalScreenPalette.phloxDefault.background) }

    /// 端末の dim（SGR 2）の見え方。完全な半分だと暗い背景では読めなくなる。
    private static let dimOpacity: Double = 0.65

    private static func color(_ channel: TerminalScreenPalette.Channel) -> Color {
        Color(
            red: Double(channel.r) / 255,
            green: Double(channel.g) / 255,
            blue: Double(channel.b) / 255
        )
    }

    /// 等幅フォント1桁ぶんの幅。フォントサイズを決めるためだけに使う。
    static func cellWidth(fontSize: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        #elseif canImport(AppKit)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        #else
        return fontSize
        #endif
        return "W".size(withAttributes: [.font: font]).width
    }
}

private struct TerminalScreenWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
