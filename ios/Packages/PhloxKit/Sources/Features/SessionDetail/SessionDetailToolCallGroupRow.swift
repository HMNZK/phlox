import SwiftUI
import DesignSystemIOS
import PhloxCore

struct SessionDetailCommandGroupRow: Identifiable, Equatable {
    let id: String
    let command: String?
    let output: String
    let isRunning: Bool
}

/// 折りたたみ時に必要な値だけを持つヘッダ表現。行データ（rows）を保持しない。
struct SessionDetailCommandGroupHeader: Equatable {
    let title: String
    let isRunning: Bool
    let shouldRender: Bool

    init(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID
        isRunning = groupIsRunning
        title = "ツール実行 ×\(items.count)"

        shouldRender = groupIsRunning || items.count == 1 || items.contains(where: Self.hasNonBlankOutput)
    }

    private static func hasNonBlankOutput(_ item: ChatMessage) -> Bool {
        guard case .command(_, _, let output) = item else {
            return false
        }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 展開時にだけ構築する行データのスライス。
struct SessionDetailCommandGroupRowsSlice: Equatable {
    let rows: [SessionDetailCommandGroupRow]
    let hiddenRowCount: Int
}

enum SessionDetailCommandGroupRowWindow {
    static let defaultLimit: Int = 50
    static let expandStep: Int = 50

    static func slice(
        items: [ChatMessage],
        lastTranscriptID: String?,
        isTurnRunning: Bool,
        limit: Int
    ) -> SessionDetailCommandGroupRowsSlice {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID

        let allRows = items.compactMap { item -> SessionDetailCommandGroupRow? in
            guard case .command(let id, let command, let output) = item else {
                return nil
            }
            return SessionDetailCommandGroupRow(
                id: id,
                command: command,
                output: output,
                isRunning: groupIsRunning && id == lastItemID
            )
        }
        // 空出力行の除外は「複数件のツールコールが並ぶときのノイズ抑制」が目的なので、
        // 唯一の行には適用しない。適用すると単独・空出力のツールコールが
        // 「ヘッダを押しても何も出ない＝どのコマンドが走ったのか分からない」状態になる。
        // 受け入れテスト: AcceptanceIOSToolCallGroupingTests
        //   「単独コマンドは出力が空でも展開でコマンド文字列を読める」/「複数件で全て空出力かつ非実行中なら従来どおり描画しない」
        let displayRows = items.count == 1 ? allRows : allRows.filter { row in
            row.isRunning || !row.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let visibleLimit = max(0, limit)
        return SessionDetailCommandGroupRowsSlice(
            rows: Array(displayRows.suffix(visibleLimit)),
            hiddenRowCount: max(0, displayRows.count - visibleLimit)
        )
    }
}

struct SessionDetailToolCallGroupRow: View {
    let items: [ChatMessage]
    let lastTranscriptID: String?
    let isTurnRunning: Bool
    let isExpanded: Bool
    let isMessageExpanded: (String) -> Bool
    let onToggleGroup: () -> Void
    let onToggleMessage: (String) -> Void
    @State private var rowLimit = SessionDetailCommandGroupRowWindow.defaultLimit

    var body: some View {
        let header = SessionDetailCommandGroupHeader(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning
        )
        if header.shouldRender {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Button(action: onToggleGroup) {
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                        Image(systemName: "terminal")
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(
                                header.isRunning ? DSColor.statusAwaitingApproval : DSColor.chatSuccess
                            )
                        Text(header.title)
                            .font(DSFont.footnote.weight(.bold))
                            .foregroundStyle(DSColor.campTextQuaternary)
                        if header.isRunning {
                            Text("実行中")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(DSColor.campTextQuaternary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    let rowsSlice = SessionDetailCommandGroupRowWindow.slice(
                        items: items,
                        lastTranscriptID: lastTranscriptID,
                        isTurnRunning: isTurnRunning,
                        limit: rowLimit
                    )
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        if rowsSlice.hiddenRowCount > 0 {
                            Button("残り \(rowsSlice.hiddenRowCount) 件を表示") {
                                rowLimit += SessionDetailCommandGroupRowWindow.expandStep
                            }
                            .accessibilityIdentifier("SessionDetailToolCallGroupRow.loadEarlierRows")
                        }
                        ForEach(rowsSlice.rows) { row in
                            commandRow(row)
                                .id(row.id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .background(DSColor.campOutputBackground, in: outputCardShape)
            .clipShape(outputCardShape)
            .accessibilityIdentifier("SessionDetailToolCallGroupRow")
        }
    }

    @ViewBuilder
    private func commandRow(_ row: SessionDetailCommandGroupRow) -> some View {
        let title = row.command.map { "$ \($0)" } ?? "$"
        let preview = SessionDetailViewModel.collapsedMessagePreview(
            for: .command(id: row.id, command: row.command, output: row.output)
        )
        let isRowExpanded = isMessageExpanded(row.id)
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Button {
                onToggleMessage(row.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(title)
                        .font(DSFont.footnote.weight(.bold))
                        .foregroundStyle(DSColor.campTextQuaternary)
                    if !isRowExpanded, !preview.isEmpty {
                        Text(preview)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isRowExpanded ? "chevron.down" : "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.campTextQuaternary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isRowExpanded, !row.output.isEmpty {
                Text(row.output)
                    .font(DSFont.campMonoCaption)
                    .tracking(-0.5)
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var outputCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
    }
}
