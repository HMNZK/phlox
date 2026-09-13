import SwiftUI
import DesignSystem

/// 新規 Claude チャットのトランスクリプト中央に出す「履歴から再開」一覧（task-9）。
struct ChatHistoryStartView: View {
    let entries: [ClaudeSessionHistoryEntry]
    var maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap
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
        VStack(spacing: DSSpacing.m) {
            header
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
                            row(for: entry)
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

    private var header: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DSColor.chatAccent)
            Text("履歴から再開")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.chatTextPrimary)
            Spacer(minLength: 0)
        }
    }

    private func row(for entry: ClaudeSessionHistoryEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.m) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(entry.preview)
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: DSSpacing.s) {
                        Text(formattedDate(entry))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.chatTextSecondary)
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
        .accessibilityIdentifier("ChatHistoryStartView.row")
    }

    private func formattedDate(_ entry: ClaudeSessionHistoryEntry) -> String {
        let date = entry.firstUserAt ?? entry.lastModified
        return Self.shortDateFormatter.string(from: date)
    }
}
