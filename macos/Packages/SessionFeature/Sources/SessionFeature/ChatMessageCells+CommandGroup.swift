import Foundation
import SwiftUI
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
        isTurnRunning: Bool,
        liveRecap: String? = nil
    ) {
        let lastItem = items.last
        isRunning = isTurnRunning && lastItem?.id == lastTranscriptID
        title = CommandGroupTitle.derive(items: items, isRunning: isRunning, liveRecap: liveRecap)

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

/// 出力の省略表示と全文表示を行単位で決める。コピー対象は常に元の出力全文。
struct CommandGroupOutputDisplay: Equatable {
    static let visibleLineLimit = 20

    let output: String
    let isExpanded: Bool

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
    let isInTranscriptViewport: Bool
    /// 実行中の最新グループだけに渡される。ADR 0116 のため同値比較には含めない。
    let recap: ((Date) -> String?)?
    @State private var isExpanded = false
    @State private var rowLimit = CommandGroupRowWindow.defaultLimit
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    init(
        items: [ChatItem],
        lastTranscriptID: String?,
        isTurnRunning: Bool,
        isInTranscriptViewport: Bool = true,
        recap: ((Date) -> String?)? = nil
    ) {
        self.items = items
        self.lastTranscriptID = lastTranscriptID
        self.isTurnRunning = isTurnRunning
        self.isInTranscriptViewport = isInTranscriptViewport
        self.recap = recap
    }

    /// ADR 0116: 未変更ブロックの body 再評価をスキップするための同値性（呼び出し側で `.equatable()`）。
    /// 比較するのは表示に効く保持値のみ。`@State`(isExpanded) と `@AppStorage`(themeID) は
    /// ビュー自身の invalidation で再評価されるため比較対象にしない（展開状態やテーマ変更は従来どおり反映される）。
    nonisolated static func == (lhs: CommandGroupCell, rhs: CommandGroupCell) -> Bool {
        lhs.items == rhs.items
            && lhs.lastTranscriptID == rhs.lastTranscriptID
            && lhs.isTurnRunning == rhs.isTurnRunning
            // viewport は実行中グループの TimelineView にだけ効く。非実行中まで
            // スクロール境界で再評価しない（ADR 0116）。
            && (!lhs.isTurnRunning || lhs.isInTranscriptViewport == rhs.isInTranscriptViewport)
    }

    var body: some View {
        let _ = themeID
        let header = CommandGroupHeader(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning,
            liveRecap: nil
        )
        if header.shouldRender {
            DisclosureCard(
                isExpanded: $isExpanded,
                title: header.title,
                subtitle: header.isRunning ? "実行中 ×\(items.count)" : "×\(items.count)",
                timestamp: header.timestamp,
                isToolCall: true,
                isTimelineVisible: isInTranscriptViewport,
                liveTitle: liveTitle
            ) {
                if isExpanded {
                    let rowsSlice = CommandGroupRowWindow.slice(
                        items: items,
                        lastTranscriptID: lastTranscriptID,
                        isTurnRunning: isTurnRunning,
                        limit: rowLimit
                    )
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        if rowsSlice.hiddenRowCount > 0 {
                            Button("残り \(rowsSlice.hiddenRowCount) 件を表示") {
                                rowLimit += CommandGroupRowWindow.expandStep
                            }
                            .accessibilityIdentifier("CommandGroupCell.loadEarlierRows")
                        }
                        ForEach(rowsSlice.rows) { row in
                            CommandGroupExecutionRow(
                                command: row.command,
                                output: row.output
                            )
                            .id(row.id)
                        }
                    }
                    .padding(.top, DSSpacing.s)
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .accessibilityIdentifier("CommandGroupCell")
        }
    }

    var liveTitle: ((Date) -> String)? {
        guard isTurnRunning, let recap else { return nil }
        return { date in
            CommandGroupTitle.derive(items: items, isRunning: true, liveRecap: recap(date))
        }
    }
}

private struct CommandGroupExecutionRow: View {
    let command: String?
    let output: String
    @State private var isOutputExpanded = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text("$ \(displayCommand)")
                .font(ChatScaledFont.mono(scale: scale))
                .foregroundStyle(DSColor.chatTextPrimary)
                .chatTextSelection()
            if !output.isEmpty {
                let outputDisplay = CommandGroupOutputDisplay(
                    output: output,
                    isExpanded: isOutputExpanded
                )
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    HStack {
                        Spacer(minLength: 0)
                        // 省略中でも描画中の prefix ではなく、元の出力全文をコピーする。
                        MessageCopyButton(
                            text: outputDisplay.copyText,
                            accessibilityIdentifier: "CommandGroupExecutionRow.copyOutput",
                            scale: scale
                        )
                    }
                    Text(outputDisplay.displayedOutput)
                        .font(ChatScaledFont.monoCaption(scale: scale))
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .chatTextSelection()
                    if outputDisplay.isTruncated {
                        Button {
                            isOutputExpanded = true
                        } label: {
                            Label(
                                "さらに \(outputDisplay.hiddenLineCount) 行を表示",
                                systemImage: "chevron.down"
                            )
                            .font(ChatScaledFont.captionStrong(scale: scale))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DSColor.chatAccent)
                        .accessibilityIdentifier("CommandGroupExecutionRow.showMoreOutput")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayCommand: String {
        guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "(コマンドなし)"
        }
        return command
    }
}
