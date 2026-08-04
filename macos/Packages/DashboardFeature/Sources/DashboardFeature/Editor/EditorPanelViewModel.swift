import Foundation
import Observation
import AgentDomain

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
    public private(set) var selectedPath: String?
    public private(set) var detail: Detail = .none
    /// 変更一覧の帰属範囲。`ListState`（表示対象の有無）とは分離して保持する。
    public private(set) var changeScope: SessionChangeScope
    var listErrorMessage: String?
    var readOnlyMessage: String?
    public var draft = "" {
        didSet {
            isDirty = loadedDiskContent.map { draft != $0 } ?? false
        }
    }
    public private(set) var isDirty = false

    // MARK: - git write workflow（ADR 0169）

    /// コミット対象として選んだパス（変更一覧のチェック）。詳細選択とは独立。
    public private(set) var pathsSelectedForCommit: Set<String> = []
    public var commitMessage = ""
    public private(set) var isWorkflowBusy = false
    public private(set) var workflowStatusMessage: String?
    public private(set) var workflowStatusIsError = false
    /// `nil` なら push 可能。非 `nil` なら理由を UI に出す。
    public private(set) var pushAvailabilityReason: String? = "リモートが設定されていません。"
    /// `nil` なら PR 作成可能。非 `nil` なら理由を UI に出す。
    public private(set) var pullRequestAvailabilityReason: String? = "GitHub CLI（gh）が利用できません。"
    public private(set) var lastPullRequestURL: String?
    /// テスト注入用。`nil` ならリポジトリルートから都度生成する。
    private let injectedWorkflowService: GitWorkflowService?

    private let service: WorkingTreeService?
    private static let maximumEditableFileSize = 1_000_000
    /// 選択時に読んだ内容。競合検出の基準であり、draft そのものではない。
    private var loadedDiskContent: String?
    private var selectionGeneration = 0

    /// バイナリや読み込みに失敗したファイルを TextEditor に渡さないための内部状態。
    var canEdit: Bool {
        selectedPath != nil && loadedDiskContent != nil
    }

    public var canCommit: Bool {
        listState == .ready
            && !pathsSelectedForCommit.isEmpty
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canPush: Bool {
        listState == .ready && pushAvailabilityReason == nil
    }

    public var canCreatePullRequest: Bool {
        listState == .ready && pullRequestAvailabilityReason == nil
    }

    public init(
        service: WorkingTreeService?,
        changeScope: SessionChangeScope = .unavailable,
        workflowService: GitWorkflowService? = nil
    ) {
        self.service = service
        self.changeScope = changeScope
        self.injectedWorkflowService = workflowService
    }

    /// 共有相手の増減など、表示対象の変更を伴わない帰属範囲の変化だけを反映する。
    public func updateChangeScope(_ changeScope: SessionChangeScope) {
        self.changeScope = changeScope
    }

    public func refresh() async {
        guard let service else {
            listState = .noProject
            listErrorMessage = nil
            changes = []
            clearSelection()
            clearWorkflowStateForMissingRepository()
            return
        }

        guard await service.isGitRepository() else {
            listState = .notARepository
            listErrorMessage = nil
            changes = []
            clearSelection()
            clearWorkflowStateForMissingRepository()
            return
        }

        do {
            changes = try await service.changes()
            listState = .ready
            listErrorMessage = nil
            pruneCommitSelection()
            await refreshWorkflowCapabilities()
        } catch {
            changes = []
            clearSelection()
            listState = .ready
            listErrorMessage = "Unable to load changes. Try refreshing."
            pathsSelectedForCommit = []
        }
    }

    public func toggleCommitSelection(for path: String) {
        if pathsSelectedForCommit.contains(path) {
            pathsSelectedForCommit.remove(path)
        } else {
            pathsSelectedForCommit.insert(path)
        }
    }

    public func refreshWorkflowCapabilities() async {
        guard listState == .ready, let workflow = await resolveWorkflowService() else {
            pushAvailabilityReason = "Git リポジトリを開けません。"
            pullRequestAvailabilityReason = "GitHub CLI（gh）が利用できません。"
            return
        }

        let remotes = await workflow.remoteNames()
        if remotes.isEmpty {
            if let remoteFailure = await workflow.remoteLookupFailureReason() {
                pushAvailabilityReason = remoteFailure
            } else {
                pushAvailabilityReason = "リモートが設定されていません。push するには remote を追加してください。"
            }
        } else {
            pushAvailabilityReason = nil
        }

        if await workflow.isGitHubCLIAvailable() {
            pullRequestAvailabilityReason = nil
        } else {
            pullRequestAvailabilityReason = "GitHub CLI（gh）が利用できません。PR 作成は不可です。"
        }
    }

    public func commitSelectedPaths() async {
        guard canCommit, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError("Git リポジトリを開けません。")
            return
        }

        isWorkflowBusy = true
        workflowStatusMessage = nil
        workflowStatusIsError = false
        let paths = pathsSelectedForCommit.sorted()
        let message = commitMessage
        do {
            // actor 上の Process 待ちは MainActor を解放する（UI 固着を避ける）。
            let sha = try await workflow.commit(paths: paths, message: message)
            workflowStatusMessage = "Committed \(String(sha.prefix(7)))."
            workflowStatusIsError = false
            commitMessage = ""
            pathsSelectedForCommit = []
            lastPullRequestURL = nil
            await refresh()
        } catch {
            presentWorkflowError(describeWorkflowError(error))
        }
        isWorkflowBusy = false
    }

    public func pushCommittedChanges() async {
        guard canPush, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError("Git リポジトリを開けません。")
            return
        }

        isWorkflowBusy = true
        workflowStatusMessage = nil
        workflowStatusIsError = false
        do {
            try await workflow.push()
            workflowStatusMessage = "Pushed to remote."
            workflowStatusIsError = false
            await refreshWorkflowCapabilities()
        } catch {
            presentWorkflowError(describeWorkflowError(error))
            await refreshWorkflowCapabilities()
        }
        isWorkflowBusy = false
    }

    public func createPullRequest() async {
        guard canCreatePullRequest, !isWorkflowBusy else { return }
        guard let workflow = await resolveWorkflowService() else {
            presentWorkflowError("Git リポジトリを開けません。")
            return
        }

        isWorkflowBusy = true
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
                title = subject.isEmpty ? "Update" : subject
            } catch {
                title = "Update"
            }
        }
        do {
            let url = try await workflow.createPullRequest(title: title, body: "")
            lastPullRequestURL = url
            workflowStatusMessage = "Pull request created."
            workflowStatusIsError = false
        } catch {
            presentWorkflowError(describeWorkflowError(error))
            await refreshWorkflowCapabilities()
        }
        isWorkflowBusy = false
    }

    public func select(_ path: String) async {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        guard let service else {
            clearSelection()
            return
        }

        do {
            let workingTreeDetail = try await service.detail(for: path)
            guard generation == selectionGeneration else { return }
            switch workingTreeDetail {
            case .binary:
                selectedPath = path
                detail = .binary
                clearDraft()
                readOnlyMessage = "Binary files cannot be edited."
            case .diff(let diff):
                selectedPath = path
                detail = .diff(diff)
                do {
                    let contents = try await service.fileContents(path)
                    guard generation == selectionGeneration else { return }
                    loadDraft(contents)
                } catch {
                    guard generation == selectionGeneration else { return }
                    clearDraft()
                    readOnlyMessage = "This file is unavailable or is not valid UTF-8. Its diff is read-only."
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
        guard let service, let selectedPath, let loadedDiskContent else {
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
        guard contents.utf8.count <= Self.maximumEditableFileSize else {
            clearDraft()
            readOnlyMessage = "This file is too large to edit here."
            return
        }

        readOnlyMessage = nil
        loadedDiskContent = contents
        draft = contents
        isDirty = false
    }

    private func clearDraft() {
        loadedDiskContent = nil
        draft = ""
        isDirty = false
    }

    private func clearSelection() {
        selectedPath = nil
        detail = .none
        readOnlyMessage = nil
        clearDraft()
    }

    private func pruneCommitSelection() {
        let visible = Set(changes.map(\.path))
        pathsSelectedForCommit = pathsSelectedForCommit.intersection(visible)
    }

    private func clearWorkflowStateForMissingRepository() {
        pathsSelectedForCommit = []
        pushAvailabilityReason = "Git リポジトリではありません。"
        pullRequestAvailabilityReason = "GitHub CLI（gh）が利用できません。"
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
        guard let error = error as? GitWorkflowError else {
            return error.localizedDescription
        }
        switch error {
        case .notARepository:
            return "Git リポジトリではありません。"
        case .noPathsSelected:
            return "コミットするファイルを選択してください。"
        case .emptyCommitMessage:
            return "コミットメッセージを入力してください。"
        case .noRemoteConfigured:
            return "リモートが設定されていません。"
        case .gitHubCLIUnavailable:
            return "GitHub CLI（gh）が利用できません。"
        case let .commandFailed(arguments, output):
            let command = arguments.joined(separator: " ")
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "git \(command) failed."
            }
            return "git \(command) failed:\n\(trimmed)"
        }
    }
}

private enum EditorPanelError: Error {
    case noEditableSelection
}
