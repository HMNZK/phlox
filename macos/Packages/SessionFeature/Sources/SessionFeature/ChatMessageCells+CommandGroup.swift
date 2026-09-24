import Foundation
import SwiftUI
import ChatRenderKit
import DesignSystem

struct CommandGroupRow: Identifiable, Equatable {
    let id: String
    let command: String?
    let output: String
    let timestamp: Date
    let isRunning: Bool
}

/// 折りたたみ時に必要な値だけを持つヘッダ表現。行データ（rows）を保持しない。
struct CommandGroupHeader: Equatable {
    let title: String
    let timestamp: Date
    let isRunning: Bool
    let shouldRender: Bool

    init(
        items: [ChatItem],
        lastTranscriptID: String?,
        isTurnRunning: Bool
    ) {
        let lastItem = items.last
        isRunning = isTurnRunning && lastItem?.id == lastTranscriptID
        title = CommandGroupTitle.derive(items: items)

        if case .commandExecution(_, _, _, let timestamp)? = lastItem {
            self.timestamp = timestamp
        } else {
            timestamp = .distantPast
        }

        shouldRender = isRunning || items.count == 1 || items.contains(where: Self.hasNonBlankOutput)
    }

    private static func hasNonBlankOutput(_ item: ChatItem) -> Bool {
        guard case .commandExecution(_, _, let output, _) = item else {
            return false
        }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 展開時にだけ構築する行データのスライス。
struct CommandGroupRowsSlice: Equatable {
    let rows: [CommandGroupRow]
    let hiddenRowCount: Int
}

// 既存の macOS 側参照を壊さないための薄い型名アダプタ。実装本体は ChatRenderKit にある。
typealias CommandToolLabel = ChatCommandToolLabel

struct CommandGroupExecutionDisplayData: Equatable {
    let label: String
    let commandBody: String
    let highlightedCommand: AttributedString
    private let collapsedOutputDisplay: CommandGroupOutputDisplay
    let copyText: String

    init(command: String?, output: String) {
        let tool = CommandToolLabel.derive(command: command)
        label = tool.label
        commandBody = tool.body
        highlightedCommand = ChatMessageRenderCache.highlightedShell(tool.body)
        collapsedOutputDisplay = CommandGroupOutputDisplay(output: output, isExpanded: false)
        let commandText = command ?? ""
        copyText = output.isEmpty ? commandText : "\(commandText)\n\n\(output)"
    }

    func outputDisplay(isExpanded: Bool) -> CommandGroupOutputDisplay {
        var display = collapsedOutputDisplay
        display.isExpanded = isExpanded
        return display
    }
}

/// 出力の省略表示と全文表示を行単位で決める。コピー対象は常に元の出力全文。
struct CommandGroupOutputDisplay: Equatable {
    static let visibleLineLimit = 20

    let output: String
    var isExpanded: Bool

    /// 出力の行分割は body 評価のたびに走るため、init で 1 回だけ行う。
    /// 計算プロパティにすると isTruncated / hiddenLineCount / displayedOutput の各参照で
    /// 出力全体を split し直し、ストリーミング中の長大出力で線形コストが積み上がる。
    private let lineCount: Int
    private let truncatedOutput: String

    init(output: String, isExpanded: Bool) {
        self.output = output
        self.isExpanded = isExpanded
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        lineCount = lines.count
        truncatedOutput = lines.prefix(Self.visibleLineLimit).joined(separator: "\n")
    }

    var isTruncated: Bool {
        !isExpanded && lineCount > Self.visibleLineLimit
    }

    var hiddenLineCount: Int {
        max(0, lineCount - Self.visibleLineLimit)
    }

    var displayedOutput: String {
        isTruncated ? truncatedOutput : output
    }

    var copyText: String { output }
}

enum CommandGroupRowWindow {
    static let defaultLimit = 50
    static let expandStep = 50

    static func slice(
        items: [ChatItem],
        lastTranscriptID: String?,
        isTurnRunning: Bool,
        limit: Int
    ) -> CommandGroupRowsSlice {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID

        let allRows = items.compactMap { item -> CommandGroupRow? in
            guard case .commandExecution(let id, let command, let output, let timestamp) = item else {
                return nil
            }
            return CommandGroupRow(
                id: id,
                command: command,
                output: output,
                timestamp: timestamp,
                isRunning: groupIsRunning && id == lastItemID
            )
        }

        let displayRows: [CommandGroupRow]
        if items.count == 1 {
            displayRows = allRows
        } else {
            displayRows = allRows.filter { row in
                row.isRunning || !row.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        let visibleLimit = max(0, limit)
        return CommandGroupRowsSlice(
            rows: Array(displayRows.suffix(visibleLimit)),
            hiddenRowCount: max(0, displayRows.count - visibleLimit)
        )
    }
}

struct CommandGroupCell: View, Equatable {
    let items: [ChatItem]
    let lastTranscriptID: String?
    let isTurnRunning: Bool
    @State private var userOverride: Bool?
    @State private var rowLimit = CommandGroupRowWindow.defaultLimit
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    init(
        items: [ChatItem],
        lastTranscriptID: String?,
        isTurnRunning: Bool
    ) {
        self.items = items
        self.lastTranscriptID = lastTranscriptID
        self.isTurnRunning = isTurnRunning
    }

    /// ADR 0116: 未変更ブロックの body 再評価をスキップするための同値性（呼び出し側で `.equatable()`）。
    /// 比較するのは表示に効く保持値のみ。`@State`(isExpanded) と `@AppStorage`(themeID) は
    /// ビュー自身の invalidation で再評価されるため比較対象にしない（展開状態やテーマ変更は従来どおり反映される）。
    nonisolated static func == (lhs: CommandGroupCell, rhs: CommandGroupCell) -> Bool {
        lhs.items == rhs.items
            && lhs.lastTranscriptID == rhs.lastTranscriptID
            && lhs.isTurnRunning == rhs.isTurnRunning
    }

    var body: some View {
        let _ = themeID
        let header = CommandGroupHeader(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning
        )
        let hasNonBlankOutput = items.contains { item in
            guard case .commandExecution(_, _, let output, _) = item else { return false }
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let presentation = TranscriptItemPresentation.command(
            path: .group,
            itemCount: items.count,
            isRunning: header.isRunning,
            hasNonBlankOutput: hasNonBlankOutput,
            runningSubtitle: "実行中",
            outputAvailableSubtitle: UIWording.text(.outputAvailable, languageCode: languageCode)
        )
        if header.shouldRender {
            TranscriptCard(
                isExpanded: Binding(
                    get: {
                        TranscriptItemPresentation.isExpanded(
                            userOverride: userOverride,
                            defaultExpanded: presentation.defaultExpanded
                        )
                    },
                    set: { userOverride = $0 }
                ),
                label: label,
                summary: summary(isRunning: header.isRunning),
                isRunning: header.isRunning,
                badges: header.isRunning
                    ? [TranscriptCardBadge(id: "running", text: Text("実行中"), color: DSColor.chatTextPrimary, weight: .medium)]
                    : singleExitBadge
            ) {
                if items.count == 1, case .commandExecution(_, _, let output, _) = items[0] {
                    // 04 A1: 1 件だけのときは「コマンド」の単独カード。中身は出力の行。
                    CommandCardOutput(output: output)
                } else {
                    let rowsSlice = CommandGroupDisplayedRows.make(
                        items: items,
                        lastTranscriptID: lastTranscriptID,
                        isTurnRunning: isTurnRunning,
                        limit: rowLimit
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        if rowsSlice.hiddenRowCount > 0 {
                            Button("残り \(rowsSlice.hiddenRowCount) 件を表示") {
                                rowLimit += CommandGroupRowWindow.expandStep
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DSColor.accentInk)
                            .font(.system(size: 11.5))
                            .padding(.leading, 28)
                            .frame(height: 24)
                            .accessibilityIdentifier("CommandGroupCell.loadEarlierRows")
                        }
                        ForEach(rowsSlice.rows) { row in
                            CommandGroupToolRow(row: row)
                                .id(row.id)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
            }
            .accessibilityIdentifier("CommandGroupCell")
        }
    }

    /// 1 件のカードだけ、出力から拾えた終了コードを右端に出す。
    private var singleExitBadge: [TranscriptCardBadge] {
        guard items.count == 1, case .commandExecution(_, _, let output, _) = items[0] else { return [] }
        return [CommandExitCode.badge(for: output)].compactMap { $0 }
    }

    /// 04 A1: 1 件はシェルなら「コマンド」、ほかはツール名。2 件以上は「ツール実行 ×n」。
    private var label: Text {
        guard items.count == 1 else { return Text("ツール実行 ×\(items.count)") }
        let tool = Self.tool(of: items[0])
        return tool.label == "Bash" ? Text("コマンド") : Text(verbatim: tool.label)
    }

    /// 見出しの等幅の要約。1 件は「$ コマンド」、実行中の束は動いているツール、ほかは「先頭 ほか n 件」。
    private func summary(isRunning: Bool) -> String {
        if items.count == 1 {
            let tool = Self.tool(of: items[0])
            return tool.label == "Bash" ? "$ \(tool.body)" : tool.body
        }
        if isRunning, let last = items.last {
            let tool = Self.tool(of: last)
            return "\(tool.label) \(tool.body)"
        }
        guard let first = items.first else { return "" }
        let tool = Self.tool(of: first)
        let head = "\(tool.label) \(Self.shortArgument(tool))"
        return String(format: AppLocalizedString.string("%@ ほか %lld 件", locale: locale), head, items.count - 1)
    }

    static func tool(of item: ChatItem) -> (label: String, body: String) {
        guard case .commandExecution(_, let command, _, _) = item else { return ("Bash", "") }
        return CommandToolLabel.derive(command: command)
    }

    /// 読み書き系のツールはファイル名だけにする（「Read ChatApprovalBroker.swift」）。
    static func shortArgument(_ tool: (label: String, body: String)) -> String {
        guard ["Read", "Write", "Edit", "NotebookEdit"].contains(tool.label) else { return tool.body }
        return tool.body.split(separator: "/").last.map(String.init) ?? tool.body
    }
}

/// 単独のコマンドカードの中身: 出力の行（20 行まで）と「さらに表示」。
struct CommandCardOutput: View {
    let output: String
    @State private var showsAll = false

    var body: some View {
        let display = CommandGroupOutputDisplay(output: output, isExpanded: showsAll)
        if !output.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TranscriptCardOutputLines(output: display.displayedOutput)
                if display.isTruncated {
                    TranscriptCardFooter(hiddenLineCount: display.hiddenLineCount, onShowMore: { showsAll = true })
                }
            }
        }
    }
}

/// 束の中の 1 ツール 1 行（高さ 24）: ツール名 44 幅 → 等幅の引数 → 右に結果（「120 行」「実行中」）。
/// 押すと、その行の出力を下に出す。
private struct CommandGroupToolRow: View {
    let row: CommandGroupRow
    @State private var showsOutput = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let tool = CommandToolLabel.derive(command: row.command)
        let hasOutput = !row.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsOutput.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text(verbatim: tool.label)
                        .font(.system(size: 12 * scale, weight: .medium))
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .lineLimit(1)
                        .frame(width: 44 * scale, alignment: .leading)
                    Text(verbatim: CommandGroupCell.shortArgument(tool))
                        .font(.system(size: 11.5 * scale, design: .monospaced))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row.isRunning {
                        Text("実行中")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .foregroundStyle(DSColor.chatTextPrimary)
                    } else if let code = CommandExitCode.parse(row.output), code != 0 {
                        Text(verbatim: "exit \(code)")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(DSColor.attentionInk(.error))
                    } else if hasOutput {
                        Text("\(Self.lineCount(row.output)) 行")
                            .font(.system(size: 11 * scale))
                            .monospacedDigit()
                            .foregroundStyle(DSColor.textTertiary)
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .frame(minHeight: 24 * scale)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasOutput)
            .accessibilityValue(hasOutput ? (showsOutput ? Text("出力を表示中") : Text("出力を隠している")) : Text(verbatim: ""))
            if showsOutput {
                CommandCardOutput(output: row.output)
            }
        }
    }

    static func lineCount(_ output: String) -> Int {
        output.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
