import Foundation
import Observation
import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

@MainActor @Observable
final class NewChatHistoryPopoverModel {
    enum State: Equatable {
        case idle
        case loading([ClaudeSessionHistoryEntry])
        case entries([ClaudeSessionHistoryEntry])
        case empty
        case failed
    }

    private(set) var state: State = .idle
    private var generation = 0

    func load(from loader: () async throws -> [ClaudeSessionHistoryEntry]) async {
        generation += 1
        let loadGeneration = generation
        let previousEntries: [ClaudeSessionHistoryEntry]
        if case .entries(let entries) = state { previousEntries = entries }
        else if case .loading(let entries) = state { previousEntries = entries }
        else { previousEntries = [] }
        state = .loading(previousEntries)
        do {
            let entries = try await loader()
            guard generation == loadGeneration else { return }
            state = entries.isEmpty ? .empty : .entries(entries)
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed
        }
    }

    func reset() {
        generation += 1
        state = .idle
    }

    var entries: [ClaudeSessionHistoryEntry] {
        switch state {
        case .entries(let entries), .loading(let entries): entries
        case .idle, .empty, .failed: []
        }
    }
}

struct NewChatHistoryPopover: View {
    @Bindable var model: NewChatHistoryPopoverModel
    let project: Project
    let usesWorktree: Bool
    let locale: Locale
    let onRetry: () -> Void
    let onSelect: (ClaudeSessionHistoryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(usesWorktree ? "選んだ会話を、新しい worktree を作って再開します" : "選んだ会話を、今の作業場所（既存ディレクトリ）で再開します")
                    .font(DSFont.auxiliary.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                Text(verbatim: (project.directoryPath as NSString).abbreviatingWithTildeInPath)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            content
                .frame(height: 300)
        }
        .padding(8)
        .frame(width: 480)
        .background(DSColor.popoverBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("履歴から再開"))
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("読み込んでいます…")
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(DSColor.fillSubtle)
                        .frame(height: 20)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .entries(let entries):
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(entries) { entry in
                        HistoryStartRow(
                            entry: entry,
                            presentation: HistoryEntryPresentation(
                                entry: entry,
                                workingDirectory: entry.sourceWorkingDirectory
                            ),
                            lastUsedText: UsageText.ago(entry.lastModified, now: .now, locale: locale),
                            locationLabel: locationLabel(for: entry),
                            locationNote: locationNote(for: entry),
                            accessibilityIdentifier: "newChat.history.entry.\(entry.sessionID)",
                            onSelect: onSelect
                        )
                    }
                }
            }
            .scrollIndicators(.automatic)
        case .empty:
            Text("履歴がありません")
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 8) {
                Text("履歴を読み込めませんでした")
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                Button("再試行", action: onRetry)
                    .accessibilityIdentifier("newChat.history.retry")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 36)
        }
    }

    private func locationLabel(for entry: ClaudeSessionHistoryEntry) -> String {
        guard let sourcePath = entry.sourceWorkingDirectory,
              Self.normalized(sourcePath) != Self.normalized(project.directoryPath) else {
            return project.name
        }
        let path = (sourcePath as NSString).expandingTildeInPath
        let key = FileManager.default.fileExists(atPath: path) ? "worktree" : "worktree（削除済み）"
        return AppLocalizedString.string(key, locale: locale)
    }

    private func locationNote(for entry: ClaudeSessionHistoryEntry) -> String? {
        guard !usesWorktree,
              let sourcePath = entry.sourceWorkingDirectory,
              Self.normalized(sourcePath) != Self.normalized(project.directoryPath) else { return nil }
        return AppLocalizedString.string("元の worktree には戻らず、既存ディレクトリで再開します", locale: locale)
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}
