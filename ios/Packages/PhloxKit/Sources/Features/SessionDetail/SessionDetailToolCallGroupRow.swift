import SwiftUI
import ChatRenderKit
import DesignSystemIOS
import PhloxCore

struct SessionDetailCommandGroupRow: Identifiable, Equatable {
    let id: String
    let command: String?
    let output: String
    let isRunning: Bool
}

enum SessionDetailCommandGroupHeaderElement: Equatable {
    case title
    case chevron
    case spacer
    case subtitle
}

/// 折りたたみ時の見出しと状態だけを保持する。
struct SessionDetailCommandGroupHeader: Equatable {
    let title: String
    let subtitle: String
    let elements: [SessionDetailCommandGroupHeaderElement]
    let isRunning: Bool
    let shouldRender: Bool

    init(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItemID = items.last?.id
        isRunning = isTurnRunning && lastItemID == lastTranscriptID
        title = "ツール実行 ×\(items.count)"
        elements = [.title, .chevron, .spacer, .subtitle]

        let commands = items.map { item -> String? in
            guard case .command(_, let command, _) = item else { return nil }
            return command
        }
        subtitle = Self.summary(commands: commands, isRunning: isRunning)
        shouldRender = isRunning || items.count == 1 || items.contains(where: Self.hasNonBlankOutput)
    }

    private static func summary(commands: [String?], isRunning: Bool) -> String {
        guard let selectedIndex = isRunning ? commands.indices.last : commands.indices.first else { return "" }
        let tool = ChatCommandToolLabel.derive(command: commands[selectedIndex])
        if isRunning {
            return "\(tool.label) \(tool.body)"
        }
        let target: String
        if ["Read", "Write", "Edit", "NotebookEdit"].contains(tool.label) {
            target = tool.body.split(separator: "/").last.map(String.init) ?? tool.body
        } else {
            target = tool.body
        }
        return "\(tool.label) \(target) ほか \(max(0, commands.count - 1)) 件"
    }

    private static func hasNonBlankOutput(_ item: ChatMessage) -> Bool {
        guard case .command(_, _, let output) = item else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 展開時にだけ構築する行データのスライス。
struct SessionDetailCommandGroupRowsSlice: Equatable {
    let rows: [SessionDetailCommandGroupRow]
    let hiddenRowCount: Int
}

enum SessionDetailCommandGroupRowWindow {
    static let defaultLimit = 50
    static let expandStep = 50

    static func slice(
        items: [ChatMessage],
        lastTranscriptID: String?,
        isTurnRunning: Bool,
        limit: Int
    ) -> SessionDetailCommandGroupRowsSlice {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID
        let allRows = items.compactMap { item -> SessionDetailCommandGroupRow? in
            guard case .command(let id, let command, let output) = item else { return nil }
            return SessionDetailCommandGroupRow(
                id: id,
                command: command,
                output: output,
                isRunning: groupIsRunning && id == lastItemID
            )
        }
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
        if items.count == 1, case .command(_, let command, let output) = items[0] {
            SessionDetailCommandCard(
                command: command,
                output: output,
                isExpanded: isExpanded,
                isRunning: header.isRunning,
                onToggle: onToggleGroup
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if header.shouldRender {
            DSChatCodeCard(isRunning: header.isRunning, showsDivider: isExpanded) {
                SessionDetailTranscriptCardHeader(
                    label: header.title,
                    summary: header.subtitle,
                    badges: header.isRunning
                        ? [SessionDetailTranscriptBadge(id: "running", text: "実行中", color: IOSColor.text.primary)]
                        : [],
                    isExpanded: isExpanded,
                    allowsDisclosure: true,
                    onToggle: onToggleGroup
                )
            } content: {
                if isExpanded {
                    let rowsSlice = SessionDetailCommandGroupRowWindow.slice(
                        items: items,
                        lastTranscriptID: lastTranscriptID,
                        isTurnRunning: isTurnRunning,
                        limit: rowLimit
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        if rowsSlice.hiddenRowCount > 0 {
                            Button("残り \(rowsSlice.hiddenRowCount) 件を表示") {
                                rowLimit += SessionDetailCommandGroupRowWindow.expandStep
                            }
                            .buttonStyle(.plain)
                            .font(DSFont.caption)
                            .foregroundStyle(IOSColor.text.secondary)
                            .frame(minHeight: DSTouch.minSize, alignment: .leading)
                            .padding(.horizontal, DSSpacing.m)
                            .accessibilityIdentifier("SessionDetailToolCallGroupRow.loadEarlierRows")
                        }
                        ForEach(Array(rowsSlice.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Rectangle()
                                    .fill(IOSColor.bg.separator)
                                    .frame(height: 1)
                            }
                            SessionDetailCommandGroupToolRow(
                                row: row,
                                isExpanded: isMessageExpanded(row.id),
                                onToggle: { onToggleMessage(row.id) }
                            )
                            .id(row.id)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("SessionDetailToolCallGroupRow")
        }
    }
}

private struct SessionDetailCommandGroupToolRow: View {
    let row: SessionDetailCommandGroupRow
    let isExpanded: Bool
    let onToggle: () -> Void

    private var tool: (label: String, body: String) {
        ChatCommandToolLabel.derive(command: row.command)
    }

    private var summary: String {
        tool.label == "Bash" ? "$ \(tool.body)" : tool.body
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: DSSpacing.xs) {
                    Text("›")
                        .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                        .foregroundStyle(IOSColor.text.tertiary)
                        .frame(width: DSSpacing.s)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(tool.label == "Bash" ? "コマンド" : tool.label)
                        .font(DSFont.sessionDetailSubtitle.weight(.semibold))
                        .foregroundStyle(IOSColor.text.primary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(summary)
                        .font(DSFont.sessionDetailTechnical)
                        .foregroundStyle(IOSColor.text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row.isRunning {
                        badge("実行中", color: IOSColor.text.primary)
                    } else if let exitCode = SessionDetailTranscriptPresentation.exitCode(in: row.output) {
                        badge("exit \(exitCode)", color: exitCode == 0 ? IOSColor.text.tertiary : IOSColor.status.error)
                    }
                }
                .padding(.horizontal, DSSpacing.m)
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                SessionDetailCommandOutputView(
                    output: row.output,
                    copyText: ChatMessageCopyText.copyText(
                        for: .command(id: row.id, command: row.command, output: row.output)
                    )
                )
            }
        }
        .accessibilityIdentifier("SessionDetailCommandGroupToolRow")
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DSFont.sessionDetailTechnical)
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize()
    }
}
