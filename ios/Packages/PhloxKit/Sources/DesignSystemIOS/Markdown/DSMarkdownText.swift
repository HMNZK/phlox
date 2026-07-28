import SwiftUI
import DesignSystem
import MarkdownUI

/// チャット本文の Markdown とフェンス付きコードを描画する View。
public struct DSMarkdownText: View {
    /// task-2 契約（凍結・PM 著）: 表をセル切り詰めなしに横スクロールで読ませるとき true。
    /// 実装と同時に反転する（flag だけの反転は虚偽報告として扱う）。
    public static let providesTableHorizontalScroll = true

    private let content: String

    public init(_ content: String) {
        self.content = content
    }

    public var body: some View {
        let blocks = MarkdownBlockParser.blocks(from: content)
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(markdown):
                    Markdown(markdown)
                        .markdownTheme(Self.theme)
                        .font(DSFont.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .code(language, code):
                    DSCodeBlock(language: language, code: code)
                case let .table(markdown):
                    HorizontallyScrollableMarkdownTable(markdown: markdown, theme: Self.theme)
                }
            }
        }
    }

    private static let theme = Theme()
        .text {
            ForegroundColor(DSColor.chatTextPrimary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            ForegroundColor(DSColor.chatAccent)
            BackgroundColor(DSColor.fillSubtle)
        }
        .link {
            ForegroundColor(DSColor.chatAccent)
        }
        // NOTE: macOS RichMarkdownView と同方針。折り返した箇条書き項目の折り返し行が次項目と
        // 重なって潰れるのを防ぐため、list 項目に限定して縦サイズを確保する（table には波及しない）。
        .listItem { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        // MarkdownUI の空テーマは段落・見出しの label に縦サイズ確保を付けない。幅制約下で
        // 折り返しても親が1行高のままにならないよう、非表ブロックだけに全行分の高さを返す。
        // 表セルはこのテーマを通らず、ADR 0045 のため表テーマへ fixedSize を追加しない。
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading1 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading2 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading3 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading4 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading5 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .heading6 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
}

/// 表本文のセル内容から、MarkdownUI へ提案する有限の幅を見積もる。
enum MarkdownTableWidthEstimator {
    /// 2400pt は iPad の横幅より十分広く、長い列を圧縮せず読ませながら、MarkdownUI へ無限の幅を
    /// 提案しないための上限。横 ScrollView 内でも常に有限の幅に保つ。
    static let maximumContentWidth: CGFloat = 2_400

    private static let minimumColumnDisplayUnits = 3
    private static let pointsPerDisplayUnit: CGFloat = 8
    private static let horizontalPaddingPerColumn: CGFloat = 32

    /// 表の各列について最大の表示幅を見積もり、本文幅を返す純関数。
    /// CJK と絵文字は英数字より概ね全角幅で描画されるため 2 単位、その他は 1 単位としている。
    static func contentWidth(for markdown: String, containerWidth: CGFloat) -> CGFloat {
        let rows = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isDelimiterRow($0) }
            .map(tableCells)
        let columnCount = rows.map(\.count).max() ?? 0
        let finiteContainerWidth = containerWidth.isFinite ? max(containerWidth, 0) : 0
        guard columnCount > 0 else {
            return finiteContainerWidth
        }

        var maximumUnits = Array(repeating: minimumColumnDisplayUnits, count: columnCount)
        for row in rows {
            for (index, cell) in row.enumerated() {
                maximumUnits[index] = max(maximumUnits[index], displayUnits(in: cell))
            }
        }

        let estimatedWidth = maximumUnits.reduce(CGFloat.zero) { partialWidth, units in
            partialWidth + CGFloat(units) * pointsPerDisplayUnit + horizontalPaddingPerColumn
        }
        return max(finiteContainerWidth, min(estimatedWidth, maximumContentWidth))
    }

    private static func tableCells(in line: Substring) -> [String] {
        let content = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        var cells: [String] = []
        var cell = ""
        var precedingBackslashCount = 0

        for character in content {
            if character == "|", precedingBackslashCount.isMultiple(of: 2) {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }

            if character == "\\" {
                precedingBackslashCount += 1
            } else {
                precedingBackslashCount = 0
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isDelimiterRow(_ line: Substring) -> Bool {
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let characters = Array(cell)
            var start = 0
            var end = characters.count

            if characters.first == ":" { start += 1 }
            if characters.last == ":" { end -= 1 }
            guard end - start >= 1 else { return false }
            return characters[start..<end].allSatisfy { $0 == "-" }
        }
    }

    private static func displayUnits(in cell: String) -> Int {
        cell.reduce(into: 0) { units, character in
            units += character.unicodeScalars.contains(where: isFullWidth) ? 2 : 1
        }
    }

    private static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
             0xF900...0xFAFF, 0xFE10...0xFE6F, 0xFF01...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1FAFF:
            true
        default:
            false
        }
    }
}

/// 表の MarkdownUI 描画へ有限の幅を渡してから横スクロールに載せる。
/// ScrollView が子に横幅 nil を提案しても、表のアンカー測定には常に有限幅だけが届く。
private struct HorizontallyScrollableMarkdownTable: View {

    let markdown: String
    let theme: Theme
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Markdown(markdown)
                .markdownTheme(theme)
                .font(DSFont.body)
                .frame(
                    width: MarkdownTableWidthEstimator.contentWidth(
                        for: markdown,
                        containerWidth: containerWidth
                    ),
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in containerWidth = width }
            }
        }
    }
}
