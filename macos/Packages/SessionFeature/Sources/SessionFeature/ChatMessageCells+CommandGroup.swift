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

struct CommandGroupPresentation: Equatable {
    let title: String
    let timestamp: Date
    let isRunning: Bool
    let rows: [CommandGroupRow]

    var shouldRender: Bool {
        isRunning || !rows.isEmpty
    }

    init(items: [ChatItem], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID
        isRunning = groupIsRunning
        title = "ツール実行 ×\(items.count)"

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
        timestamp = allRows.last?.timestamp ?? .distantPast
        rows = allRows.filter { row in
            row.isRunning || !row.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct CommandGroupCell: View {
    let items: [ChatItem]
    let lastTranscriptID: String?
    let isTurnRunning: Bool
    @State private var isExpanded = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        let presentation = CommandGroupPresentation(
            items: items,
            lastTranscriptID: lastTranscriptID,
            isTurnRunning: isTurnRunning
        )
        if presentation.shouldRender {
            DisclosureCard(
                isExpanded: $isExpanded,
                title: presentation.title,
                subtitle: presentation.isRunning ? "実行中" : nil,
                timestamp: presentation.timestamp,
                systemImage: "terminal",
                accent: presentation.isRunning ? DSColor.statusAwaitingApproval : DSColor.chatSuccess,
                status: presentation.isRunning ? .running : .complete
            ) {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    ForEach(presentation.rows) { row in
                        CommandExecutionCell(
                            command: row.command,
                            output: row.output,
                            timestamp: row.timestamp,
                            isRunning: row.isRunning
                        )
                        .id(row.id)
                    }
                }
                .padding(.top, DSSpacing.s)
            }
            .frame(maxWidth: 800, alignment: .leading)
            .accessibilityIdentifier("CommandGroupCell")
        }
    }
}
