import DesignSystem
import Foundation
import Observation
import AgentDomain
import Combine

@MainActor
@Observable
public final class EditorPanelViewModel {
    public enum ListState: Equatable, Sendable {
        case noProject
        case notARepository
        case ready
    }

    public enum Detail: Equatable, Sendable {
        case none
        case diff(String)
        case content(String)
        case binary
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflictDetected
    }

    public private(set) var listState: ListState = .noProject
    public private(set) var changes: [WorkingTreeChange] = []
    public private(set) var stagedChanges: [WorkingTreeChange] = []
    public private(set) var unstagedChanges: [WorkingTreeChange] = []
    public private(set) var conflictedPaths: [String] = []
    private(set) var stagedLineCounts: [String: WorkingTreeLineCount] = [:]
    private(set) var unstagedLineCounts: [String: WorkingTreeLineCount] = [:]
    public private(set) var selectedSource: WorkingTreeSource = .worktree
    public private(set) var gitSelection: GitChangeSelection?
    var activeGitRow: GitHistoryRowID?
    var historyCommits: [GitHistoryCommit] = []
    var localBranches: [GitBranch] = []
    var remoteBranches: [GitBranch] = []
    var gitStashes: [GitStash] = []
    var graphRows: [GitGraphRow] = []
    var historyFiles: [WorkingTreeSource: [WorkingTreeChange]] = [:]
    var expandedHistoryRows: Set<WorkingTreeSource> = []
    var openHistorySections: Set<GitHistorySection> = []
    var loadedHistorySections: Set<GitHistorySection> = []
    var loadingHistorySections: Set<GitHistorySection> = []
    var hasMoreCommits = false
    var loadedCommitLimit = 50
    var hasMoreGraph = false
    var loadedGraphLimit = 200
    var lastFetchDate: Date?
    public var stashFocusToken = 0
    public func requestStashInput() { stashFocusToken &+= 1 }
    public private(set) var aheadCount = 0
    public private(set) var hasUpstream = false
    public private(set) var selectedPath: String?
    public private(set) var detail: Detail = .none
    /// 変更一覧の帰属範囲。`ListState`（表示対象の有無）とは分離して保持する。
    public private(set) var changeScope: SessionChangeScope
    var listErrorMessage: String?
    var readOnlyMessage: String?
    public private(set) var isReadOnly = false
    private var draftContent = ""
    public var draft: String {
        get { draftContent }
        set {
            guard !isReadOnly else { return }
            draftContent = newValue
            isDirty = loadedDiskContent.map { newValue != $0 } ?? false
        }
    }
    var syntaxHighlightingEnabled: Bool {
        if case .diff = detail { return shouldHighlightPreview(isDiff: true) }
        return shouldHighlightPreview(isDiff: false)
    }

    func shouldHighlightPreview(isDiff: Bool) -> Bool {
        isDiff || loadedDiskContent != nil && WorkingTreeText.shouldHighlight(draft)
    }
    public private(set) var isDirty = false
    public private(set) var isRefreshing = false
    private(set) var branchLabel = ""
    private(set) var lineCounts: [String: WorkingTreeLineCount] = [:]
    private(set) var freshPaths: Set<String> = []
    private(set) var newChangeCount = 0
    private(set) var refreshRevision = 0
    private var previousPaths: Set<String>?
    private var refreshPending = false
    var commitFocusToken = 0

    public var commitMessageFocused = false

    public func requestCommitFocus() { commitFocusToken &+= 1 }
    func takeCommitFocusRequest() -> Bool {
        guard commitFocusToken > 0 else { return false }
        commitFocusToken = 0
        return true
    }
    func markGitPathSeen(_ path: String) { freshPaths.remove(path) }

    func gitDetail(for path: String, source: WorkingTreeSource = .worktree) async throws -> WorkingTreeDetail {
        guard let service else { throw WorkingTreeServiceError.notRepository }
        return try await service.detail(for: path, source: source)
    }

    func acceptSnapshot(_ snapshot: WorkingTreeSnapshot) {
        let sorted = snapshot.changes.sorted { $0.path < $1.path }
        freshPaths = GitTabPolicy.newPaths(previous: previousPaths, changes: sorted)
        newChangeCount = freshPaths.count
        previousPaths = Set(sorted.map(\.path))
        changes = sorted
        stagedChanges = snapshot.stagedChanges.sorted { $0.path < $1.path }
        unstagedChanges = snapshot.unstagedChanges.sorted { $0.path < $1.path }
        conflictedPaths = snapshot.conflictedPaths
        stagedLineCounts = snapshot.stagedLineCounts
        unstagedLineCounts = snapshot.unstagedLineCounts
        branchLabel = snapshot.branch
        lineCounts = snapshot.lineCounts
        listState = .ready
        listErrorMessage = nil
        refreshRevision &+= 1
    }

    func setSnapshotNotRepository() {
        clearHistoryState()
        listState = .notARepository
        listErrorMessage = nil
        changes = []
        stagedChanges = []
        unstagedChanges = []
        conflictedPaths = []
        stagedLineCounts = [:]
        unstagedLineCounts = [:]
        branchLabel = ""
        lineCounts = [:]
        freshPaths = []
        newChangeCount = 0
        if !isDirty { clearSelection() }
        clearWorkflowStateForMissingRepository()
    }

    // MARK: - Git の書き込み操作（ADR 0204）

    public var commitMessage = ""
    public private(set) var isWorkflowBusy = false
    /// 実行中の Git 操作（07「コミットしています…」とボタンの「コミット中…」）。
    public private(set) var runningOperation: GitOperation?
    var runningRepositoryAction: GitRepositoryAction?
    public private(set) var workflowStatusMessage: String?
    public private(set) var workflowStatusIsError = false
    /// `nil` なら push 可能。非 `nil` なら理由を UI に出す。
    public private(set) var pushAvailabilityReason: String? = EditorPanelViewModel.localized("リモートが設定されていません。")
    /// `nil` なら PR 作成可能。非 `nil` なら理由を UI に出す。
    public private(set) var pullRequestAvailabilityReason: String? = EditorPanelViewModel.localized("GitHub CLI（gh）が利用できません。")
    public private(set) var lastPullRequestURL: String?
    /// テスト注入用。`nil` ならリポジトリルートから都度生成する。
    private let injectedWorkflowService: GitWorkflowService?

    private let service: WorkingTreeService?
    private var fileChangeSubscription: AnyCancellable?
    /// 選択時に読んだ内容。競合検出の基準であり、draft そのものではない。
    private var loadedDiskContent: String?
    private var selectionGeneration = 0
    /// 取得待ちの選択競合を実際の共有モデルで検査するための差分読み取り口。
    var detailLoader: (@MainActor (String, WorkingTreeSource) async throws -> WorkingTreeDetail)?


    /// バイナリや読み込みに失敗したファイルを TextEditor に渡さないための内部状態。
    var canEdit: Bool {
        canViewContent && !isReadOnly
    }

    var canViewContent: Bool { selectedPath != nil && loadedDiskContent != nil }

    public var canCommit: Bool {
        listState == .ready
            && !stagedChanges.isEmpty
            && conflictedPaths.isEmpty
            && !isWorkflowBusy
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canPush: Bool {
        listState == .ready && pushAvailabilityReason == nil && !isWorkflowBusy
    }

    public var canCreatePullRequest: Bool {
        listState == .ready && pullRequestAvailabilityReason == nil && !isWorkflowBusy
    }

    public init(
        service: WorkingTreeService?,
        changeScope: SessionChangeScope = .unavailable,
        workflowService: GitWorkflowService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.service = service
        self.changeScope = changeScope
        self.injectedWorkflowService = workflowService
        if service != nil {
            fileChangeSubscription = notificationCenter.publisher(for: .fileTreeFileSaved).sink { [weak self] notification in
                guard let root = notification.userInfo?["root"] as? String,
                      notification.userInfo?["path"] is String else { return }
                Task { @MainActor [weak self] in
                    guard let self, let service = self.service else { return }
                    let repositoryRoot = await service.resolvedRepositoryRootPath()
                    guard GitTabPolicy.shouldRefresh(.fileChanged(root: root), projectRoot: repositoryRoot) else { return }
                    await self.refresh()
                }
            }
        }
    }

    /// 共有相手の増減など、表示対象の変更を伴わない帰属範囲の変化だけを反映する。
    public func updateChangeScope(_ changeScope: SessionChangeScope) {
        self.changeScope = changeScope
    }

    public func refresh() async {
        if isRefreshing { refreshPending = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            await refreshOnce()
        } while refreshPending && !Task.isCancelled
    }

    private func refreshOnce() async {
        guard let service else {
            clearHistoryState()
            listState = .noProject
            listErrorMessage = nil
            changes = []
            stagedChanges = []
            unstagedChanges = []
            conflictedPaths = []
            stagedLineCounts = [:]
            unstagedLineCounts = [:]
            clearSelection()
            clearWorkflowStateForMissingRepository()
            return
        }

        do {
            let snapshot = try await service.snapshot()
            guard !Task.isCancelled else { return }
            acceptSnapshot(snapshot)
            let previousActiveRow = activeGitRow
            if let selectedPath, !isDirty {
                if selectedSource.isHistory {
                    await select(selectedPath, source: selectedSource)
                } else if (selectedSource == .staged ? stagedChanges : unstagedChanges).contains(where: { $0.path == selectedPath }) {
                    await select(selectedPath, source: selectedSource)
                } else if (selectedSource == .staged ? unstagedChanges : stagedChanges).contains(where: { $0.path == selectedPath }) {
                    await select(selectedPath, source: selectedSource == .staged ? .worktree : .staged)
                } else { clearSelection() }
            }
            switch previousActiveRow {
            case .change(let item), .file(let item, _):
                if gitSelection == item { activeGitRow = previousActiveRow }
            case .none: break
            default: activeGitRow = previousActiveRow
            }
            await refreshWorkflowCapabilities()
            loadedHistorySections = []
            historyFiles = [:]
            for section in GitHistorySection.allCases where openHistorySections.contains(section) {
                await loadHistorySection(section)
            }
            for source in expandedHistoryRows { await loadHistoryFiles(source) }
        } catch WorkingTreeServiceError.notRepository {
            setSnapshotNotRepository()
        } catch {
            changes = []
            stagedChanges = []
            unstagedChanges = []
            conflictedPaths = []
            stagedLineCounts = [:]
            unstagedLineCounts = [:]
            if !isDirty { clearSelection() }
            listState = .ready
            lineCounts = [:]
            freshPaths = []
            newChangeCount = 0
            if case WorkingTreeServiceError.gitCommandFailed(let arguments, let output) = error {
                listErrorMessage = "git " + arguments.joined(separator: " ") + "\n" + output.trimmingCharacters(in: .whitespacesAndNewlines)
            } else { listErrorMessage = error.localizedDescription }
        }
    }

    public func stage(paths: [String]) async { await changeStaging(paths: paths, source: .worktree) }
    public func unstage(paths: [String]) async { await changeStaging(paths: paths, source: .staged) }
    public func stageAll() async { await stage(paths: unstagedChanges.map(\.path)) }
    public func unstageAll() async { await unstage(paths: stagedChanges.map(\.path)) }

    func setHistorySection(_ section: GitHistorySection, expanded: Bool) async {
        if expanded {
            openHistorySections.insert(section)
            if !loadedHistorySections.contains(section) { await loadHistorySection(section) }
        } else { openHistorySections.remove(section) }
    }

    private func clearHistoryState() {
        historyCommits = []; localBranches = []; remoteBranches = []; gitStashes = []; graphRows = []
        historyFiles = [:]; loadedHistorySections = []; expandedHistoryRows = []
        hasMoreCommits = false
        hasMoreGraph = false
        lastFetchDate = nil
    }

    func loadHistorySection(_ section: GitHistorySection) async {
        guard let service, listState == .ready, !loadingHistorySections.contains(section) else { return }
        loadingHistorySections.insert(section)
        defer { loadingHistorySections.remove(section) }
        do {
            switch section {
            case .commits:
                let commits = try await service.history(limit: loadedCommitLimit + 1)
                hasMoreCommits = commits.count > loadedCommitLimit
                historyCommits = Array(commits.prefix(loadedCommitLimit))
            case .branches: localBranches = try await service.branches()
            case .remotes:
                remoteBranches = try await service.branches(remote: true)
                lastFetchDate = try await service.lastFetchDate()
            case .stashes: gitStashes = try await service.stashes()
            case .graph:
                let commits = try await service.history(limit: loadedGraphLimit + 1, all: true)
                hasMoreGraph = commits.count > loadedGraphLimit
                graphRows = GitGraphRow.make(Array(commits.prefix(loadedGraphLimit)))
            }
            loadedHistorySections.insert(section)
        } catch { presentWorkflowError(describeWorkflowError(error)) }
    }

    func loadMoreCommits() async {
        guard let service, hasMoreCommits, !loadingHistorySections.contains(.commits) else { return }
        loadingHistorySections.insert(.commits)
        defer { loadingHistorySections.remove(.commits) }
        do {
            let next = try await service.history(skip: historyCommits.count, limit: 51)
            hasMoreCommits = next.count > 50
            historyCommits += next.prefix(50)
            loadedCommitLimit = historyCommits.count
        } catch { presentWorkflowError(describeWorkflowError(error)) }
    }

    func loadMoreGraph() async {
        guard let service, hasMoreGraph, !loadingHistorySections.contains(.graph) else { return }
        loadingHistorySections.insert(.graph)
        defer { loadingHistorySections.remove(.graph) }
        do {
            let limit = graphRows.count + 200
            let commits = try await service.history(limit: limit + 1, all: true)
            hasMoreGraph = commits.count > limit
            graphRows = GitGraphRow.make(Array(commits.prefix(limit)))
            loadedGraphLimit = graphRows.count
        } catch { presentWorkflowError(describeWorkflowError(error)) }
    }

    func toggleHistoryRow(_ source: WorkingTreeSource) async {
        if expandedHistoryRows.contains(source) { expandedHistoryRows.remove(source) }
        else {
            expandedHistoryRows.insert(source)
            if historyFiles[source] == nil { await loadHistoryFiles(source) }
        }
    }

    private func loadHistoryFiles(_ source: WorkingTreeSource) async {
        guard let service else { return }
        do { historyFiles[source] = try await service.historyFiles(source: source) }
        catch { presentWorkflowError(describeWorkflowError(error)) }
    }

    func branchIsMerged(_ name: String) async -> Bool? {
        guard let service else { return nil }
        do { return try await service.isBranchMerged(name) }
        catch { presentWorkflowError(describeWorkflowError(error)); return nil }
    }

    public func fetchGitRemotes() async { await performRepositoryAction(.fetch) }

    func performRepositoryAction(_ action: GitRepositoryAction) async {
        guard !isWorkflowBusy, listState == .ready else { return }
        dismissWorkflowStatus()
        isWorkflowBusy = true
        runningRepositoryAction = action
        runningOperation = switch action {
        case .fetch: .fetch
        case .stash, .applyStash, .popStash, .dropStash: .stash
        default: .branch
        }
        defer { isWorkflowBusy = false; runningOperation = nil; runningRepositoryAction = nil }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError(Self.localized("Git リポジトリを開けません。")); return
        }
        do { try await workflow.perform(action) }
        catch { presentWorkflowError(describeWorkflowError(error)) }
        // pop の衝突など、失敗時も一部のファイルが変わり得る。
        await refresh()
    }

    func visibleGitRows(changesExpanded: Bool) -> [GitChangeSelection] {
        guard changesExpanded else { return [] }
        return stagedChanges.map { .init(path: $0.path, source: .staged) }
            + unstagedChanges.map { .init(path: $0.path, source: .worktree) }
    }

    func moveGitSelection(by offset: Int, changesExpanded: Bool) async {
        let items = visibleGitRows(changesExpanded: changesExpanded)
        guard !items.isEmpty else { return }
        let index = gitSelection.flatMap { items.firstIndex(of: $0) } ?? (offset > 0 ? -1 : items.count)
        let next = items[min(max(index + offset, 0), items.count - 1)]
        await select(next.path, source: next.source)
    }

    public func toggleSelectedStaging(changesExpanded: Bool = true) async {
        guard let selection = gitSelection,
              visibleGitRows(changesExpanded: changesExpanded).contains(selection) else { return }
        await changeStaging(paths: [selection.path], source: selection.source)
    }

    private func changeStaging(paths: [String], source: WorkingTreeSource) async {
        guard !isWorkflowBusy, !paths.isEmpty else { return }
        dismissWorkflowStatus()
        isWorkflowBusy = true
        runningOperation = source == .staged ? .unstage : .stage
        defer {
            isWorkflowBusy = false
            runningOperation = nil
        }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError(Self.localized("Git リポジトリを開けません。"))
            return
        }
        let group = source == .staged ? stagedChanges : unstagedChanges
        let movedPaths = Set(paths)
        let anchor = group.firstIndex { movedPaths.contains($0.path) } ?? 0
        let nextPath = group.dropFirst(anchor + 1).first { !movedPaths.contains($0.path) }?.path
        do {
            if source == .staged { try await workflow.unstage(paths: paths) }
            else { try await workflow.stage(paths: paths) }
            await refresh()
            if let nextPath { await select(nextPath, source: source) }
            else { clearSelection() }
        } catch {
            await refresh()
            presentWorkflowError(describeWorkflowError(error))
        }
    }

    public func refreshWorkflowCapabilities() async {
        guard listState == .ready, let workflow = await resolveWorkflowService() else {
            pushAvailabilityReason = Self.localized("Git リポジトリを開けません。")
            pullRequestAvailabilityReason = Self.localized("GitHub CLI（gh）が利用できません。")
            return
        }

        let remotes = await workflow.remoteNames()
        if remotes.isEmpty {
            if let remoteFailure = await workflow.remoteLookupFailureReason() {
                pushAvailabilityReason = remoteFailure
            } else {
                pushAvailabilityReason = Self.localized("リモートが設定されていません。プッシュするにはリモートを追加してください。")
            }
        } else {
            pushAvailabilityReason = nil
        }

        do {
            let state = try await workflow.pushState()
            hasUpstream = state.hasUpstream
            aheadCount = try await workflow.aheadCount()
            if pushAvailabilityReason == nil {
                if !state.hasCommit {
                    pushAvailabilityReason = Self.localized("初回コミット前はプッシュできません。")
                } else if !state.hasBranch {
                    pushAvailabilityReason = Self.localized("detached HEAD ではプッシュできません。ブランチを作成してください。")
                } else if state.hasUpstream && aheadCount == 0 {
                    pushAvailabilityReason = Self.localized("プッシュするコミットがありません。")
                }
            }
        } catch {
            aheadCount = 0
            pushAvailabilityReason = describeWorkflowError(error)
        }
        if await workflow.isGitHubCLIAvailable() {
            do {
                pullRequestAvailabilityReason = try await workflow.hasPushedBranch()
                    ? nil : Self.localized("PR を作成するには先にプッシュしてください。")
            } catch { pullRequestAvailabilityReason = describeWorkflowError(error) }
        } else {
            pullRequestAvailabilityReason = Self.localized("GitHub CLI（gh）が利用できません。PR 作成は不可です。")
        }
    }

    public func commitStagedChanges() async {
        guard canCommit, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError(Self.localized("Git リポジトリを開けません。"))
            return
        }

        isWorkflowBusy = true
        runningOperation = .commit
        workflowStatusMessage = nil
        workflowStatusIsError = false
        let message = commitMessage
        do {
            // actor 上の Process 待ちは MainActor を解放する（UI 固着を避ける）。
            let sha = try await workflow.commit(message: message)
            workflowStatusMessage = String(format: Self.localized("%@ をコミットしました。"), String(sha.prefix(7)))
            workflowStatusIsError = false
            commitMessage = ""
            lastPullRequestURL = nil
            await refresh()
        } catch {
            presentWorkflowError(describeWorkflowError(error))
        }
        isWorkflowBusy = false
        runningOperation = nil
    }

    public func pushCommittedChanges() async {
        guard canPush, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError(Self.localized("Git リポジトリを開けません。"))
            return
        }

        isWorkflowBusy = true
        runningOperation = .push
        workflowStatusMessage = nil
        workflowStatusIsError = false
        do {
            try await workflow.push()
            workflowStatusMessage = Self.localized("リモートへプッシュしました。")
            workflowStatusIsError = false
            await refresh()
        } catch {
            presentWorkflowError(describeWorkflowError(error))
            await refreshWorkflowCapabilities()
        }
        isWorkflowBusy = false
        runningOperation = nil
    }

    public func createPullRequest() async {
        guard canCreatePullRequest, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError(Self.localized("Git リポジトリを開けません。"))
            return
        }

        isWorkflowBusy = true
        runningOperation = .pullRequest
        workflowStatusMessage = nil
        workflowStatusIsError = false
        let typedTitle = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if !typedTitle.isEmpty {
            title = typedTitle
        } else {
            // commit 成功後はメッセージ欄を空にするため、直近コミット subject を既定にする。
            do {
                let subject = try await workflow.latestCommitSubject()
                title = subject.isEmpty ? "更新" : subject
            } catch {
                title = "更新"
            }
        }
        do {
            let url = try await workflow.createPullRequest(title: title, body: "")
            lastPullRequestURL = url
            workflowStatusMessage = Self.localized("プルリクエストを作成しました。")
            workflowStatusIsError = false
        } catch {
            presentWorkflowError(describeWorkflowError(error))
            await refreshWorkflowCapabilities()
        }
        isWorkflowBusy = false
        runningOperation = nil
    }

    public func select(_ path: String, source: WorkingTreeSource = .worktree) async {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        guard let service else {
            clearSelection()
            return
        }

        do {
            let workingTreeDetail: WorkingTreeDetail
            if let detailLoader { workingTreeDetail = try await detailLoader(path, source) }
            else { workingTreeDetail = try await service.detail(for: path, source: source) }
            guard generation == selectionGeneration else { return }
            selectedSource = source
            gitSelection = .init(path: path, source: source)
            let item = GitChangeSelection(path: path, source: source)
            let graph: Bool
            if case .file(let current, let isGraph) = activeGitRow, current == item { graph = isGraph }
            else { graph = false }
            activeGitRow = source.isHistory ? .file(item, graph: graph) : .change(item)
            switch workingTreeDetail {
            case .binary:
                selectedPath = path
                detail = .binary
                clearDraft()
                readOnlyMessage = "バイナリファイルは編集できません。"
            case .diff(let diff):
                selectedPath = path
                detail = .diff(diff)
                do {
                    let contents = try await service.fileContents(path, source: source)
                    guard generation == selectionGeneration else { return }
                    loadDraft(contents)
                    if source != .worktree { isReadOnly = true }
                } catch {
                    guard generation == selectionGeneration else { return }
                    clearDraft()
                    readOnlyMessage = "このファイルは利用できないか、有効なUTF-8ではありません。差分は読み取り専用です。"
                }
            case .untrackedContent(let contents):
                selectedPath = path
                detail = .content(contents)
                loadDraft(contents)
            }
        } catch {
            guard generation == selectionGeneration else { return }
            // 非 UTF-8・削除済み・不正パスを UI へ例外として出さない。
            clearSelection()
        }
    }

    public func save() async throws -> SaveResult {
        let (service, path, expectedDiskContent) = try editableSelection()
        let savedDraft = draft
        let generation = selectionGeneration
        switch try await service.save(path: path, content: savedDraft, expectedDiskContent: expectedDiskContent) {
        case .saved:
            await reloadAfterSaving(path, savedDraft: savedDraft, generation: generation)
            return .saved
        case .conflict:
            return .conflictDetected
        }
    }

    public func overwrite() async throws {
        let (service, path, _) = try editableSelection()
        let savedDraft = draft
        let generation = selectionGeneration
        _ = try await service.save(path: path, content: savedDraft, expectedDiskContent: nil)
        await reloadAfterSaving(path, savedDraft: savedDraft, generation: generation)
    }

    private func editableSelection() throws -> (WorkingTreeService, String, String) {
        guard canEdit, let service, let selectedPath, let loadedDiskContent else {
            throw EditorPanelError.noEditableSelection
        }
        return (service, selectedPath, loadedDiskContent)
    }

    private func reloadAfterSaving(_ path: String, savedDraft: String, generation: Int) async {
        await refresh()
        guard generation == selectionGeneration, selectedPath == path else { return }
        guard draft == savedDraft else {
            loadedDiskContent = savedDraft
            isDirty = true
            return
        }
        await select(path)
    }

    private func loadDraft(_ contents: String) {
        let byteCount = contents.utf8.count
        guard byteCount <= WorkingTreeText.maximumReadableFileSize else {
            clearDraft()
            readOnlyMessage = "このファイルは大きすぎるため、ここでは編集できません。"
            return
        }

        isReadOnly = false
        loadedDiskContent = contents
        draft = contents
        isReadOnly = byteCount > WorkingTreeText.maximumEditableFileSize
        readOnlyMessage = isReadOnly ? String(format: Self.localized("閲覧のみ（%@ MB を超えるため）"),
                                            String(WorkingTreeText.maximumEditableFileSize / 1_000_000)) : nil
        isDirty = false
    }

    private func clearDraft() {
        isReadOnly = false
        loadedDiskContent = nil
        draft = ""
        isDirty = false
    }

    private func clearSelection() {
        selectedPath = nil
        gitSelection = nil
        activeGitRow = nil
        detail = .none
        readOnlyMessage = nil
        clearDraft()
    }

    private func clearWorkflowStateForMissingRepository() {
        pushAvailabilityReason = Self.localized("Git リポジトリではありません。")
        pullRequestAvailabilityReason = Self.localized("GitHub CLI（gh）が利用できません。")
        lastPullRequestURL = nil
    }

    private func resolveWorkflowService() async -> GitWorkflowService? {
        if let injectedWorkflowService {
            return injectedWorkflowService
        }
        if let root = changeScope.repositoryRoot, !root.isEmpty {
            return GitWorkflowService(
                repositoryRoot: URL(fileURLWithPath: root, isDirectory: true)
            )
        }
        guard let service, let path = await service.resolvedRepositoryRootPath(), !path.isEmpty else {
            return nil
        }
        return GitWorkflowService(
            repositoryRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    /// 状態メッセージを閉じる。長い失敗出力でボタンが画面外へ押し出されたあとの復旧経路。
    public func dismissWorkflowStatus() {
        workflowStatusMessage = nil
        workflowStatusIsError = false
    }

    /// テストと内部から失敗／成功メッセージを載せる。
    func presentWorkflowError(_ message: String) {
        workflowStatusMessage = message
        workflowStatusIsError = true
    }

    private func describeWorkflowError(_ error: Error) -> String {
        if case WorkingTreeServiceError.gitCommandFailed(let arguments, let output) = error {
            return "git " + arguments.joined(separator: " ") + "\n" + output
        }
        guard let error = error as? GitWorkflowError else {
            return error.localizedDescription
        }
        switch error {
        case .notARepository:
            return Self.localized("Git リポジトリではありません。")
        case .noPathsSelected, .noStagedChanges:
            return Self.localized("コミットするファイルをステージしてください。")
        case .emptyCommitMessage:
            return Self.localized("コミットメッセージを入力してください。")
        case .unmergedChanges:
            return Self.localized("競合をターミナルなどで解消してください")
        case .noRemoteConfigured:
            return Self.localized("リモートが設定されていません。")
        case .gitHubCLIUnavailable:
            return Self.localized("GitHub CLI（gh）が利用できません。")
        case let .commandFailed(arguments, output):
            let command = arguments.joined(separator: " ")
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return String(format: Self.localized("git %@ が失敗しました。"), command)
            }
            // git の出力は訳さない（C-45）。
            return String(format: Self.localized("git %@ が失敗しました:"), command) + "\n" + trimmed
        }
    }

    /// 状態の文言はアプリの表示言語で作る（C-45）。
    private static func localized(_ key: String) -> String {
        AppLocalizedString.string(key, locale: TerminalPanelSession.displayLocale)
    }
}

/// コミット欄の Git 操作。
public enum GitOperation: Sendable {
    case fetch
    case stash
    case branch
    case stage
    case unstage
    case commit
    case push
    case pullRequest
}

enum EditorPanelError: Error, Equatable {
    case noEditableSelection
}
