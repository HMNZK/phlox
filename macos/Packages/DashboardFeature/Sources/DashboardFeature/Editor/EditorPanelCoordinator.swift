import Foundation
import Observation
import AgentDomain

/// エディタパネルの対象と変更一覧 VM の遷移を管理する状態機械。
///
/// View はセッション・作業ツリーの変化を `update` へ転送し、表示中の target を
/// `resolve` へ渡すだけにする。VM の同一性と、その VM が解決済みの target は
/// 同じ遷移として扱い、対象の切替時には同時に無効化する。
@MainActor
@Observable
final class EditorPanelCoordinator {
    private(set) var viewModel = EditorPanelViewModel(service: nil)
    private(set) var target = EditorPanelTarget(
        selectedSessionID: nil,
        workingDirectory: nil,
        peerCount: 0
    )
    @ObservationIgnored private var resolvedTarget: EditorPanelTarget?

    /// セッション選択または共有相手の変化を反映する。
    ///
    /// 選択セッション・作業ディレクトリが同じなら VM を維持し、peerCount だけが
    /// 変わった場合は target の更新だけで注記の再解決を可能にする。表示対象の
    /// 同一性が変わった場合は VM と resolvedTarget を同時に無効化する。
    func update(selectedSessionID: SessionID?, workspaces: [SessionWorkspace]) {
        let nextTarget = EditorPanelTargetPolicy.target(
            selectedSessionID: selectedSessionID,
            workspaces: workspaces
        )
        guard target != nextTarget else { return }

        let targetIdentityChanged = !hasSameIdentity(target, nextTarget)
        target = nextTarget
        guard targetIdentityChanged else { return }

        viewModel = EditorPanelViewModel(service: nil)
        resolvedTarget = nil
    }

    /// 現在の target に対応する git スコープと変更一覧を解決する。
    ///
    /// `.task(id:)` のキャンセルと、View からの高速な target 更新の両方に備え、
    /// 非同期処理の前後で target を再確認する。共有相手の増減だけなら既存 VM を
    /// 保持して帰属範囲だけを更新する。
    func resolve(workspaces: [SessionWorkspace]) async {
        let target = self.target

        guard let selectedSessionID = target.selectedSessionID else {
            viewModel.updateChangeScope(.unavailable)
            await viewModel.refresh()
            guard !Task.isCancelled, self.target == target else { return }
            resolvedTarget = target
            return
        }

        let targetIdentityChanged = !hasSameIdentity(resolvedTarget, target)
        let cachedRoot = viewModel.changeScope.repositoryRoot
        let repositoryRoot: String?
        // 同一 identity でも cachedRoot が nil なら取り直す。
        // 初回が非 git / 未作成で nil だったあと git init や worktree 生成が
        // 追いついた場合に、一覧だけ復帰して帰属注記が永久に出ないのを防ぐ。
        if targetIdentityChanged || cachedRoot == nil,
           let workingDirectory = target.workingDirectory,
           !workingDirectory.isEmpty {
            let service = WorkingTreeService(
                repositoryRoot: URL(fileURLWithPath: workingDirectory, isDirectory: true)
            )
            repositoryRoot = await service.resolvedRepositoryRootPath()
        } else {
            repositoryRoot = cachedRoot
        }

        let scope = SessionChangeScopeResolver.resolve(
            selectedSessionID: selectedSessionID,
            workspaces: workspaces,
            repositoryRootProvider: { path in
                guard path == target.workingDirectory else { return nil }
                return repositoryRoot
            }
        )

        guard !Task.isCancelled, self.target == target else { return }

        guard targetIdentityChanged else {
            viewModel.updateChangeScope(scope)
            await viewModel.refresh()
            guard !Task.isCancelled, self.target == target else { return }
            resolvedTarget = target
            return
        }

        let repositoryPath = scope.repositoryRoot ?? target.workingDirectory
        let service = repositoryPath.flatMap { path -> WorkingTreeService? in
            guard !path.isEmpty else { return nil }
            return WorkingTreeService(
                repositoryRoot: URL(fileURLWithPath: path, isDirectory: true)
            )
        }
        let resolvedViewModel = EditorPanelViewModel(
            service: service,
            changeScope: scope
        )
        viewModel = resolvedViewModel
        await resolvedViewModel.refresh()
        guard !Task.isCancelled, self.target == target else { return }
        resolvedTarget = target
    }

    private func hasSameIdentity(
        _ lhs: EditorPanelTarget?,
        _ rhs: EditorPanelTarget
    ) -> Bool {
        guard let lhs else { return false }
        return hasSameIdentity(lhs, rhs)
    }

    private func hasSameIdentity(
        _ lhs: EditorPanelTarget,
        _ rhs: EditorPanelTarget
    ) -> Bool {
        lhs.selectedSessionID == rhs.selectedSessionID
            && lhs.workingDirectory == rhs.workingDirectory
    }
}
