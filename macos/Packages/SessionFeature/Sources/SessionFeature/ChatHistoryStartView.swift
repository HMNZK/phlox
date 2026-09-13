import SwiftUI
import DesignSystem

/// 新規 Claude/Codex チャットのトランスクリプト中央に出す「続きから再開」一覧。
struct ChatHistoryStartView: View {
    let entries: [ClaudeSessionHistoryEntry]
    var maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap
    let workingDirectory: String?
    let onSelect: (ClaudeSessionHistoryEntry) -> Void

    @State private var presentations: [String: HistoryEntryPresentation]

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale.current
        return formatter
    }()

    init(
        entries: [ClaudeSessionHistoryEntry],
        maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap,
        workingDirectory: String?,
        onSelect: @escaping (ClaudeSessionHistoryEntry) -> Void
    ) {
        self.entries = entries
        self.maxCardHeight = maxCardHeight
        self.workingDirectory = workingDirectory
        self.onSelect = onSelect
        _presentations = State(
            initialValue: Self.makePresentations(
                entries: entries,
                workingDirectory: workingDirectory
            )
        )
    }

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            header
            newSessionHint
            if entries.isEmpty {
                Text("履歴がありません")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.xl)
            } else {
                ScrollView {
                    LazyVStack(spacing: DSSpacing.xs) {
                        ForEach(entries) { entry in
                            if let presentation = presentations[entry.id] {
                                row(for: entry, presentation: presentation)
                            }
                        }
                    }
                }
                .frame(maxHeight: maxCardHeight)
            }
        }
        .frame(maxWidth: 560)
        .padding(DSSpacing.l)
        .background(DSColor.chatElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        )
        .dsShadow(.cardHover)
        .accessibilityIdentifier("ChatHistoryStartView")
        .task(id: HistoryPresentationInputs(entries: entries, workingDirectory: workingDirectory)) {
            presentations = Self.makePresentations(
                entries: entries,
                workingDirectory: workingDirectory
            )
        }
        .onChange(of: HistoryPresentationInputs(entries: entries, workingDirectory: workingDirectory)) { _, inputs in
            presentations = Self.makePresentations(
                entries: inputs.entries,
                workingDirectory: inputs.workingDirectory
            )
        }
    }

    private static func makePresentations(
        entries: [ClaudeSessionHistoryEntry],
        workingDirectory: String?
    ) -> [String: HistoryEntryPresentation] {
        Dictionary(
            entries.map { entry in
                (entry.id, HistoryEntryPresentation(entry: entry, workingDirectory: workingDirectory))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DSColor.chatAccent)
            Text("続きから再開")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.chatTextPrimary)
            Spacer(minLength: 0)
        }
    }

    private var newSessionHint: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text("新規作成")
                .font(DSFont.caption)
                .foregroundStyle(DSColor.chatTextSecondary)
            Text("下の入力欄から新しい依頼を始めます")
                .font(DSFont.caption)
                .foregroundStyle(DSColor.chatTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for entry: ClaudeSessionHistoryEntry, presentation: HistoryEntryPresentation) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(presentation.title)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(presentation.fullTitle)
                    HStack(spacing: DSSpacing.s) {
                        Text(presentation.projectName)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.chatTextSecondary)
                            .lineLimit(1)
                            .help(presentation.projectPath ?? "")
                        Text("最終利用")
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.chatTextSecondary)
                        Text(formattedLastUsed(presentation.lastUsedAt))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.chatTextSecondary)
                            .lineLimit(1)
                        if let branch = entry.gitBranch, !branch.isEmpty {
                            Text(branch)
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.chatTextSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .foregroundStyle(DSColor.chatTextSecondary)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(DSColor.chatCard.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.sessionID)
        .accessibilityLabel(
            presentation.fullTitle
                + " "
                + presentation.accessibilityDetails(
                    lastUsedText: formattedLastUsed(presentation.lastUsedAt)
                )
                + " "
                + entry.sessionID
        )
        .accessibilityIdentifier("ChatHistoryStartView.row")
    }

    private func formattedLastUsed(_ date: Date?) -> String {
        guard let date else { return "最終利用日時不明" }
        return Self.shortDateFormatter.string(from: date)
    }
}

private struct HistoryPresentationInputs: Equatable {
    var entries: [ClaudeSessionHistoryEntry]
    var workingDirectory: String?
}
