import SwiftUI
import DesignSystem

/// 新規 Claude/Codex チャットのトランスクリプト中央に出す「続きから再開」一覧。
struct ChatHistoryStartView: View {
    let entries: [ClaudeSessionHistoryEntry]
    /// 件数と最後の発言（読み終えたものだけ）。
    var summaries: [String: ChatHistorySummary] = [:]
    var maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap
    let workingDirectory: String?
    let onSelect: (ClaudeSessionHistoryEntry) -> Void
    /// 「Claude Code」など。説明文に出す。
    var agentName: String = ""
    /// 「新しい会話を始める」（一覧を閉じて入力欄へ）。
    var onStartNew: (() -> Void)?

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
        summaries: [String: ChatHistorySummary] = [:],
        maxCardHeight: CGFloat = ChatHistoryStartLayout.maxCardHeightCap,
        workingDirectory: String?,
        agentName: String = "",
        onSelect: @escaping (ClaudeSessionHistoryEntry) -> Void,
        onStartNew: (() -> Void)? = nil
    ) {
        self.entries = entries
        self.summaries = summaries
        self.maxCardHeight = maxCardHeight
        self.workingDirectory = workingDirectory
        self.agentName = agentName
        self.onSelect = onSelect
        self.onStartNew = onStartNew
        _presentations = State(
            initialValue: Self.makePresentations(
                entries: entries,
                workingDirectory: workingDirectory
            )
        )
    }

    /// PhloxChat.dc.html の isHistory: 上寄せ・枠なし。見出し 17/700 と説明 → 幅 560 の行カード → 「新しい会話を始める ⌘↩」。
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("過去の会話から再開")
                    .font(DSFont.sheetTitle)
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(projectName) で \(agentName) と行った会話です。選ぶと続きから再開します。")
                    .font(DSFont.dense)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if entries.isEmpty {
                Text("履歴がありません")
                    .font(DSFont.row)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            if let presentation = presentations[entry.id] {
                                HistoryStartRow(
                                    entry: entry,
                                    presentation: presentation,
                                    summary: summaries[entry.id],
                                    lastUsedText: formattedLastUsed(presentation.lastUsedAt),
                                    onSelect: onSelect
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxHeight: maxCardHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let onStartNew {
                Button(action: onStartNew) {
                    HStack(spacing: 6) {
                        Text("新しい会話を始める")
                            .font(DSFont.dense)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: "⌘↩")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DSColor.controlBorder, lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("ChatHistoryStartView.startNew")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DSColor.chatBackground)
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

    private var projectName: String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "" }
        return URL(fileURLWithPath: (workingDirectory as NSString).expandingTildeInPath).lastPathComponent
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

    private func formattedLastUsed(_ date: Date?) -> String {
        guard let date else { return "最終利用日時不明" }
        return Self.shortDateFormatter.string(from: date)
    }
}

/// 1 件の行カード: 左に題名 13/600 と 2 行目（最後の発言。読み終える前はプロジェクト）、右に日時と等幅の「件数 · ブランチ」。
/// ポインタを置いた行はホバー色の地＋2pt のアクセント枠、ほかは 1pt の区切り線の枠。
private struct HistoryStartRow: View {
    let entry: ClaudeSessionHistoryEntry
    let presentation: HistoryEntryPresentation
    let summary: ChatHistorySummary?
    let lastUsedText: String
    let onSelect: (ClaudeSessionHistoryEntry) -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(DSFont.row.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .help(presentation.fullTitle)
                    Group {
                        if let lastMessage = summary?.lastMessage {
                            Text("最後: \(lastMessage)")
                        } else {
                            Text(presentation.projectName)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .help(presentation.projectPath ?? "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(lastUsedText)
                    if let meta = Self.meta(summary: summary, branch: entry.gitBranch) {
                        meta
                            .font(DSFont.monoCaption)
                            .lineLimit(1)
                    }
                }
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isHovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DSColor.fillSubtle)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isHovering ? DSColor.accent : DSColor.separator, lineWidth: isHovering ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.sessionID)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("ChatHistoryStartView.row")
    }

    private var accessibilityText: String {
        let details = presentation.accessibilityDetails(lastUsedText: lastUsedText)
        return presentation.fullTitle + " " + details + Self.accessibilitySummary(summary) + " " + entry.sessionID
    }

    /// 読み上げに件数と最後の発言を足す（画面の 2 行目と右下に出している分）。
    static func accessibilitySummary(_ summary: ChatHistorySummary?) -> String {
        guard let summary else { return "" }
        let count = summary.reachesLimit
            ? String(localized: "\(summary.messageCount) 件以上")
            : String(localized: "history.messageCount \(summary.messageCount)")
        guard let lastMessage = summary.lastMessage else { return " " + count }
        return " " + count + " " + String(localized: "最後: \(lastMessage)")
    }

    /// 「18 件 · feat/approval-expiry」。件数は読み終えてから、ブランチは分かるときだけ。
    static func meta(summary: ChatHistorySummary?, branch: String?) -> Text? {
        let branch = branch.flatMap { $0.isEmpty ? nil : $0 }
        let count: Text? = summary.map { summary in
            // 「%lld 件」の既存キーは英語が sessions なので、発言の件数は日本語訳つきの別キーにする。
            summary.reachesLimit ? Text("\(summary.messageCount) 件以上") : Text("history.messageCount \(summary.messageCount)")
        }
        switch (count, branch) {
        case let (count?, branch?): return Text("\(count) · \(Text(verbatim: branch))")
        case let (count?, nil): return count
        case let (nil, branch?): return Text(verbatim: branch)
        case (nil, nil): return nil
        }
    }
}

private struct HistoryPresentationInputs: Equatable {
    var entries: [ClaudeSessionHistoryEntry]
    var workingDirectory: String?
}
