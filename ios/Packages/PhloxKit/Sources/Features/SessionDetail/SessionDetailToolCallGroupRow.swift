import SwiftUI
import DesignSystemIOS
import PhloxCore

struct SessionDetailCommandGroupRow: Identifiable, Equatable {
    let id: String
    let command: String?
    let output: String
    let isRunning: Bool
}

struct SessionDetailCommandGroupPresentation: Equatable {
    let title: String
    let isRunning: Bool
    let rows: [SessionDetailCommandGroupRow]

    var shouldRender: Bool {
        isRunning || !rows.isEmpty
    }

    init(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID
        isRunning = groupIsRunning
        title = "ツール実行 ×\(items.count)"

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
        rows = allRows.filter { row in
            row.isRunning || !row.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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

    var body: some View {
        let presentation = SessionDetailCommandGroupPresentation(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning
        )
        if presentation.shouldRender {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Button(action: onToggleGroup) {
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                        Image(systemName: "terminal")
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(
                                presentation.isRunning ? DSColor.statusAwaitingApproval : DSColor.chatSuccess
                            )
                        Text(presentation.title)
                            .font(DSFont.footnote.weight(.bold))
                            .foregroundStyle(DSColor.campTextQuaternary)
                        if presentation.isRunning {
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
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        ForEach(presentation.rows) { row in
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
