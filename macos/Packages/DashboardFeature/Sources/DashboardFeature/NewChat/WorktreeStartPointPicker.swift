import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

private struct WorktreeStartPointSnapshotItemsKey: EnvironmentKey {
    static let defaultValue: [WorktreeStartPointItem]? = nil
}

extension EnvironmentValues {
    /// 画面外の描画でも実際のポップオーバーの内容を使う。
    var worktreeStartPointSnapshotItems: [WorktreeStartPointItem]? {
        get { self[WorktreeStartPointSnapshotItemsKey.self] }
        set { self[WorktreeStartPointSnapshotItemsKey.self] = newValue }
    }
}

struct WorktreeStartPointPicker: View {
    @Bindable var draft: NewChatDraft
    let projectID: ProjectID?
    let directory: String?
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle
    @Environment(\.worktreeStartPointSnapshotItems) private var snapshotItems
    @State private var items: [WorktreeStartPointItem] = [.init(point: .head)]
    @State private var query = ""
    @State private var directCommit: WorktreeStartPoint?

    private var selected: WorktreeStartPoint { draft.worktreeStartPoint(projectID: projectID, directory: directory) }
    private var candidates: [WorktreeStartPointItem] {
        let base = snapshotItems ?? items
        guard let directCommit, !base.contains(where: { $0.point == directCommit }) else { return base }
        return base + [.init(point: directCommit)]
    }
    private var options: [SelectablePopoverOption] {
        candidates.map { item in
            .init(id: item.point.revision, title: item.point.title(locale: locale, bundle: bundle),
                  sectionTitle: item.point.sectionKey.map(localized), detail: item.summary,
                  isSelected: item.point == selected)
        }
    }

    var body: some View {
        SelectablePopoverButton(
            options: options, selectedID: selected.revision,
            accessibilityLabel: localized("ワークツリーの起点"),
            accessibilityValue: selected.title(locale: locale, bundle: bundle),
            accessibilityIdentifier: "newChat.worktreeStartPointPicker",
            width: DSLayout.harnessMenuWidth, maxHeight: DSLayout.harnessMenuHeight,
            searchText: $query, searchPrompt: localized("起点を絞り込む、またはコミット ID を入力"),
            searchAccessibilityIdentifier: "newChat.worktreeStartPointSearch",
            isEnabled: directory != nil, showsFocusRing: true,
            onOpen: reloadItems,
            onSelect: choose
        ) { _ in
            NewChatChipLabel(title: selected.title(locale: locale, bundle: bundle),
                             systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                             usesMiddleTruncation: true, allowsTruncation: true)
        }
        .task(id: directory) {
            items = [.init(point: .head)]
            query = ""
            directCommit = nil
            await reloadItems()
        }
        .task(id: query + "\n" + (directory ?? "")) {
            directCommit = nil
            let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let directory, WorktreeStartPoint.isCommitID(input) else { return }
            let commit = try? await WorkingTreeService(repositoryRoot: URL(fileURLWithPath: directory)).worktreeCommit(matching: input)
            guard !Task.isCancelled else { return }
            directCommit = commit
        }
        .overlay(alignment: .topTrailing) {
            if snapshotItems != nil {
                SelectablePopover(options: options, selectedID: selected.revision,
                                  width: DSLayout.harnessMenuWidth, maxHeight: DSLayout.harnessMenuHeight,
                                  searchText: $query, searchPrompt: localized("起点を絞り込む、またはコミット ID を入力"),
                                  searchAccessibilityIdentifier: "newChat.worktreeStartPointSearch",
                                  accessibilityIdentifier: "newChat.worktreeStartPointPicker.popover",
                                  onSelect: choose)
                    .offset(y: DSLayout.controlChipHeight)
            }
        }
    }

    private func choose(_ option: SelectablePopoverOption) {
        guard let point = candidates.first(where: { $0.point.revision == option.id })?.point else { return }
        draft.selectWorktreeStartPoint(point, projectID: projectID, directory: directory)
    }

    private func reloadItems() async {
        guard let directory else { return }
        let loaded = await WorkingTreeService(repositoryRoot: URL(fileURLWithPath: directory)).worktreeStartPoints()
        guard !Task.isCancelled else { return }
        items = loaded
    }

    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }
}
