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

    init(items: [ChatItem], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItem = items.last
        isRunning = isTurnRunning && lastItem?.id == lastTranscriptID
        title = "ツール実行 ×\(items.count)"

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
    @State private var isExpanded = false
    @State private var rowLimit = CommandGroupRowWindow.defaultLimit
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

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
        if header.shouldRender {
            DisclosureCard(
                isExpanded: $isExpanded,
                title: header.title,
                subtitle: header.isRunning ? "実行中" : nil,
                timestamp: header.timestamp,
                systemImage: "terminal",
                accent: header.isRunning ? DSColor.statusAwaitingApproval : DSColor.chatSuccess,
                status: header.isRunning ? .running : .complete
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
            }
            .frame(maxWidth: 800, alignment: .leading)
            .accessibilityIdentifier("CommandGroupCell")
        }
    }
}
