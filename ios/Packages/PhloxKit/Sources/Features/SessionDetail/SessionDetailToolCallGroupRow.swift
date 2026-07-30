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

/// 折りたたみ時に必要な値だけを持つヘッダ表現。行データ（rows）を保持しない。
struct SessionDetailCommandGroupHeader: Equatable {
    let title: String
    let subtitle: String?
    let elements: [SessionDetailCommandGroupHeaderElement]
    let isRunning: Bool
    let shouldRender: Bool

    init(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool) {
        let lastItemID = items.last?.id
        let groupIsRunning = isTurnRunning && lastItemID == lastTranscriptID
        isRunning = groupIsRunning
        let commands = items.map { item -> String? in
            guard case .command(_, let command, _) = item else {
                return nil
            }
            return command
        }
        title = ChatCommandGroupTitle.derive(commands: commands, itemCount: items.count)
        subtitle = nil
        elements = [.title, .chevron, .spacer]

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
        //   「単独コマンドは出力が空でも展開でコマンド文字列を読める」/「複数件で全て空出力かつ完了済みなら従来どおり描画しない」
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
                        Text(header.title)
                            .font(DSFont.footnote.weight(.bold))
                            .foregroundStyle(DSColor.campTextQuaternary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(DSColor.campTextQuaternary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
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
            // グループ自体は器を持たない（見出しと展開状態だけ）。器は中身のコマンドカードが持つ。
            // 外側にも背景を敷くと、ファイル変更カードと見た目が割れ、カードの入れ子で枠が二重になる（ADR 0147）。
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("SessionDetailToolCallGroupRow")
        }
    }

    private func commandRow(_ row: SessionDetailCommandGroupRow) -> some View {
        SessionDetailCommandCard(
            command: row.command,
            output: row.output,
            isExpanded: isMessageExpanded(row.id),
            onToggle: { onToggleMessage(row.id) }
        )
    }
}
