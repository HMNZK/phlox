import SwiftUI
import DesignSystem

/// 新規 Claude/Codex チャットのトランスクリプト中央に出す「続きから再開」一覧。
struct ChatHistoryStartView: View {
    let entries: [ClaudeSessionHistoryEntry]
    var maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap
    let workingDirectory: String?
    let onSelect: (ClaudeSessionHistoryEntry) -> Void

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale.current
        return formatter
    }()

    var body: some View {
        let presentationsByID = presentationsBySessionID()
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
                            row(for: entry, presentation: presentationsByID[entry.id]!)
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
    }

    private func presentationsBySessionID() -> [String: HistoryEntryPresentation] {
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
        .accessibilityLabel(presentation.fullTitle + " " + entry.sessionID)
        .accessibilityIdentifier("ChatHistoryStartView.row")
    }

    private func formattedLastUsed(_ date: Date?) -> String {
        guard let date else { return "最終利用日時不明" }
        return Self.shortDateFormatter.string(from: date)
    }
}
