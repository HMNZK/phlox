import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

// task-43 受け入れテスト（PM 著・不変）。ComposerDestinationLabel / teamDestination 未実装の
// コンパイル RED が正常。期待値は tasks/task-43.md のリテラル。
// 既存 AgoraComposerRouting.action と TeamComposerTarget.resolveRootSessionID を実際に呼ぶ。
// ルーティングをモックに置き換えない。

private struct TeamPhaseCase: Sendable {
    let phase: AgoraDiscussionPhase?
    let canStart: Bool
    let expected: String
}

@Suite("Acceptance: チーム composer 送信先表示の合成（task-43）")
struct AcceptanceTeamComposerDestinationLabelTests {

    private func composedLabel(
        phase: AgoraDiscussionPhase?,
        canStartDiscussion: Bool,
        rootProjectName: String?,
        rootTaskName: String?,
        hasDestination: Bool = true,
        isReadyForInput: Bool = true,
        hasContent: Bool = true,
        actionText: String = ""
    ) -> String {
        let action = AgoraComposerRouting.action(
            phase: phase,
            canStartDiscussion: canStartDiscussion,
            text: actionText
        )
        let destination = ComposerDestinationLabel.teamDestination(
            action: action,
            rootProjectName: rootProjectName,
            rootTaskName: rootTaskName
        )
        return ComposerDestinationLabel.text(
            for: destination,
            hasDestination: hasDestination,
            isReadyForInput: isReadyForInput,
            hasContent: hasContent
        )
    }

    // MARK: - 契約の phase 表

    @Test("既存 action と teamDestination と text を合成した phase 表")
    func phaseTableLiterals() {
        let cases: [TeamPhaseCase] = [
            TeamPhaseCase(phase: nil, canStart: true, expected: "討論を開始"),
            TeamPhaseCase(phase: nil, canStart: false, expected: "親セッションへの送信"),
            TeamPhaseCase(phase: .idle, canStart: true, expected: "討論を開始"),
            TeamPhaseCase(phase: .idle, canStart: false, expected: "親セッションへの送信"),
            TeamPhaseCase(phase: .discussing, canStart: true, expected: "討論への発言"),
            TeamPhaseCase(phase: .discussing, canStart: false, expected: "討論への発言"),
            TeamPhaseCase(phase: .concluding, canStart: true, expected: "討論への発言"),
            TeamPhaseCase(phase: .concluding, canStart: false, expected: "討論への発言"),
            TeamPhaseCase(phase: .ended(.stopped), canStart: true, expected: "討論を開始"),
            TeamPhaseCase(phase: .ended(.stopped), canStart: false, expected: "親セッションへの送信"),
            TeamPhaseCase(phase: .ended(.utteranceLimitReached), canStart: true, expected: "討論を開始"),
            TeamPhaseCase(phase: .ended(.utteranceLimitReached), canStart: false, expected: "親セッションへの送信"),
        ]
        #expect(cases.count == 12)
        for item in cases {
            #expect(
                composedLabel(
                    phase: item.phase,
                    canStartDiscussion: item.canStart,
                    rootProjectName: nil,
                    rootTaskName: nil
                ) == item.expected
            )
        }
    }

    @Test("終了後を自動的に親送信と扱わない")
    func endedIsNotAutomaticallyParentSend() {
        #expect(
            composedLabel(
                phase: .ended(.stopped),
                canStartDiscussion: true,
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            ) == "討論を開始"
        )
        #expect(
            composedLabel(
                phase: .ended(.utteranceLimitReached),
                canStartDiscussion: true,
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            ) == "討論を開始"
        )
    }

    @Test("開始不可を自動的に送信不可とも扱わない")
    func cannotStartIsNotAutomaticallySendBlocked() {
        #expect(
            composedLabel(
                phase: .idle,
                canStartDiscussion: false,
                rootProjectName: nil,
                rootTaskName: nil,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信"
        )
        #expect(
            composedLabel(
                phase: .ended(.stopped),
                canStartDiscussion: false,
                rootProjectName: nil,
                rootTaskName: nil
            ) == "親セッションへの送信"
        )
    }

    @Test(".concluding は討論外扱いせず 討論への発言")
    func concludingRemainsDiscussionUtterance() {
        #expect(
            composedLabel(
                phase: .concluding,
                canStartDiscussion: false,
                rootProjectName: "Garden",
                rootTaskName: "子の調査"
            ) == "討論への発言"
        )
    }

    // MARK: - 討論開始でも既存条件が足りなければ送信不可理由

    @Test("討論開始の action でも宛先なしなら送信先がありません")
    func startDiscussionWithoutTargetAddsMissingDestination() {
        #expect(
            composedLabel(
                phase: .idle,
                canStartDiscussion: true,
                rootProjectName: nil,
                rootTaskName: nil,
                hasDestination: false,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始 — 送信不可（送信先がありません）"
        )
    }

    @Test("討論開始の action でも未準備なら入力を受け付けられません")
    func startDiscussionWithoutReadinessAddsNotReady() {
        #expect(
            composedLabel(
                phase: nil,
                canStartDiscussion: true,
                rootProjectName: nil,
                rootTaskName: nil,
                hasDestination: true,
                isReadyForInput: false,
                hasContent: true
            ) == "討論を開始 — 送信不可（入力を受け付けられません）"
        )
    }

    @Test("討論開始の action でも本文なしならメッセージを入力してください")
    func startDiscussionWithoutContentAddsNeedMessage() {
        #expect(
            composedLabel(
                phase: .idle,
                canStartDiscussion: true,
                rootProjectName: nil,
                rootTaskName: nil,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: false
            ) == "討論を開始 — 送信不可（メッセージを入力してください）"
        )
    }

    // MARK: - 討論進行中はカード名・本文・議題が混入しない

    @Test("討論進行中は選択カード・根の名前が変わっても 討論への発言")
    func discussingIgnoresCardAndRootNames() {
        #expect(
            composedLabel(
                phase: .discussing,
                canStartDiscussion: true,
                rootProjectName: "Phlox",
                rootTaskName: "全体作業",
                actionText: "議題と本文を混入させない"
            ) == "討論への発言"
        )
        #expect(
            composedLabel(
                phase: .discussing,
                canStartDiscussion: false,
                rootProjectName: "Garden",
                rootTaskName: "子の調査",
                actionText: "カード名"
            ) == "討論への発言"
        )
        let label = composedLabel(
            phase: .concluding,
            canStartDiscussion: true,
            rootProjectName: "Garden",
            rootTaskName: "子の調査",
            actionText: "議題A"
        )
        #expect(label == "討論への発言")
        #expect(!label.contains("Phlox"))
        #expect(!label.contains("Garden"))
        #expect(!label.contains("全体作業"))
        #expect(!label.contains("子の調査"))
        #expect(!label.contains("議題A"))
        #expect(!label.contains("議題と本文を混入させない"))
    }

    @Test("action の本文・議題は表示しない")
    func actionPayloadDoesNotAppearInLabel() {
        let start = composedLabel(
            phase: .idle,
            canStartDiscussion: true,
            rootProjectName: "Phlox",
            rootTaskName: "全体作業",
            actionText: "この議題は出さない"
        )
        #expect(start == "討論を開始")
        #expect(!start.contains("この議題は出さない"))
        let parent = composedLabel(
            phase: .idle,
            canStartDiscussion: false,
            rootProjectName: "Phlox",
            rootTaskName: "全体作業",
            actionText: "親へ送る本文"
        )
        #expect(parent == "Phlox / 全体作業 — 親セッションへの送信")
        #expect(!parent.contains("親へ送る本文"))
    }

    // MARK: - 実 resolver

    @Test("選択した子が Garden / 子の調査、根が Phlox / 全体作業 なら親送信は根")
    func resolverChildUsesRootNames() {
        let root = SessionID()
        let child = SessionID()
        let parentByID: [SessionID: SessionID?] = [root: nil, child: root]
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: child, parentByID: parentByID) == root)

        let names: [SessionID: (project: String, task: String)] = [
            child: ("Garden", "子の調査"),
            root: ("Phlox", "全体作業"),
        ]
        let resolved = TeamComposerTarget.resolveRootSessionID(selectedSessionID: child, parentByID: parentByID)
        #expect(resolved == root)
        let rootNames = names[resolved!]
        #expect(rootNames?.project == "Phlox")
        #expect(rootNames?.task == "全体作業")
        let destination = ComposerDestinationLabel.teamDestination(
            action: AgoraComposerRouting.action(phase: .idle, canStartDiscussion: false, text: ""),
            rootProjectName: rootNames?.project,
            rootTaskName: rootNames?.task
        )
        #expect(
            ComposerDestinationLabel.text(
                for: destination,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("子→親→根の複数段は resolver の根を使う")
    func resolverWalksChildParentRoot() {
        let root = SessionID()
        let parent = SessionID()
        let child = SessionID()
        let parentByID: [SessionID: SessionID?] = [root: nil, parent: root, child: parent]
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: child, parentByID: parentByID) == root)
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: parent, parentByID: parentByID) == root)
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: root, parentByID: parentByID) == root)

        let names: [SessionID: (project: String, task: String)] = [
            child: ("Garden", "子の調査"),
            parent: ("Garden", "中間"),
            root: ("Phlox", "全体作業"),
        ]
        let resolved = TeamComposerTarget.resolveRootSessionID(selectedSessionID: child, parentByID: parentByID)!
        let rootNames = names[resolved]!
        let destination = ComposerDestinationLabel.teamDestination(
            action: .legacyRootSend(""),
            rootProjectName: rootNames.project,
            rootTaskName: rootNames.task
        )
        #expect(
            ComposerDestinationLabel.text(
                for: destination,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("選択なしと未知の選択 ID は既存 resolver の nil")
    func resolverNilSelectionAndUnknownID() {
        let root = SessionID()
        let parentByID: [SessionID: SessionID?] = [root: nil]
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: nil, parentByID: parentByID) == nil)
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: SessionID(), parentByID: parentByID) == nil)

        let destination = ComposerDestinationLabel.teamDestination(
            action: AgoraComposerRouting.action(phase: .idle, canStartDiscussion: false, text: ""),
            rootProjectName: nil,
            rootTaskName: nil
        )
        #expect(
            ComposerDestinationLabel.text(
                for: destination,
                hasDestination: false,
                isReadyForInput: true,
                hasContent: true
            ) == "親セッションへの送信 — 送信不可（送信先がありません）"
        )
    }

    @Test("親欠損は既存 resolver の返り値を使い、新しい探索規則を定義しない")
    func resolverMissingParentUsesExistingReturn() {
        let known = SessionID()
        let unknownParent = SessionID()
        let parentByID: [SessionID: SessionID?] = [known: unknownParent]
        let resolved = TeamComposerTarget.resolveRootSessionID(selectedSessionID: known, parentByID: parentByID)
        #expect(resolved == known)

        let names: [SessionID: (project: String, task: String)] = [
            known: ("Phlox", "全体作業"),
        ]
        let rootNames = names[resolved!]!
        let destination = ComposerDestinationLabel.teamDestination(
            action: .legacyRootSend(""),
            rootProjectName: rootNames.project,
            rootTaskName: rootNames.task
        )
        #expect(
            ComposerDestinationLabel.text(
                for: destination,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("循環は既存 resolver の返り値を使い、新しい探索規則を定義しない")
    func resolverCycleUsesExistingReturn() {
        let a = SessionID()
        let b = SessionID()
        let parentByID: [SessionID: SessionID?] = [a: b, b: a]
        let resolved = TeamComposerTarget.resolveRootSessionID(selectedSessionID: a, parentByID: parentByID)
        #expect(resolved != nil)

        let names: [SessionID: (project: String, task: String)] = [
            a: ("Phlox", "循環A"),
            b: ("Garden", "循環B"),
        ]
        let rootNames = names[resolved!]!
        let destination = ComposerDestinationLabel.teamDestination(
            action: .legacyRootSend(""),
            rootProjectName: rootNames.project,
            rootTaskName: rootNames.task
        )
        let label = ComposerDestinationLabel.text(
            for: destination,
            hasDestination: true,
            isReadyForInput: true,
            hasContent: true
        )
        #expect(
            label == "Phlox / 循環A — 親セッションへの送信"
                || label == "Garden / 循環B — 親セッションへの送信"
        )
    }

    @Test("同じ名前のセッションを別プロジェクトに置き、名前一致で取り違えない")
    func sameTaskNameDifferentProjectsDoNotCollide() {
        let phloxRoot = SessionID()
        let gardenRoot = SessionID()
        let gardenChild = SessionID()
        let parentByID: [SessionID: SessionID?] = [
            phloxRoot: nil,
            gardenRoot: nil,
            gardenChild: gardenRoot,
        ]
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: gardenChild, parentByID: parentByID) == gardenRoot)
        #expect(TeamComposerTarget.resolveRootSessionID(selectedSessionID: phloxRoot, parentByID: parentByID) == phloxRoot)

        let names: [SessionID: (project: String, task: String)] = [
            phloxRoot: ("Phlox", "全体作業"),
            gardenRoot: ("Garden", "全体作業"),
            gardenChild: ("Garden", "子の調査"),
        ]
        let resolved = TeamComposerTarget.resolveRootSessionID(selectedSessionID: gardenChild, parentByID: parentByID)!
        #expect(resolved == gardenRoot)
        let rootNames = names[resolved]!
        #expect(rootNames.project == "Garden")
        let destination = ComposerDestinationLabel.teamDestination(
            action: AgoraComposerRouting.action(phase: .idle, canStartDiscussion: false, text: ""),
            rootProjectName: rootNames.project,
            rootTaskName: rootNames.task
        )
        #expect(
            ComposerDestinationLabel.text(
                for: destination,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Garden / 全体作業 — 親セッションへの送信"
        )
    }

    // MARK: - 単一・グリッドの conversation は討論状態に影響されない

    @Test("単一・グリッドの conversation 表示は討論 phase に影響されない")
    func conversationIgnoresDiscussionPhase() {
        let phases: [AgoraDiscussionPhase?] = [
            nil,
            .idle,
            .discussing,
            .concluding,
            .ended(.stopped),
            .ended(.utteranceLimitReached),
        ]
        for phase in phases {
            _ = phase
            #expect(
                ComposerDestinationLabel.text(
                    for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                    hasDestination: true,
                    isReadyForInput: true,
                    hasContent: true
                ) == "Phlox / 入力欄改善"
            )
            #expect(
                ComposerDestinationLabel.text(
                    for: .conversation(projectName: "Garden", taskName: "調査"),
                    hasDestination: true,
                    isReadyForInput: true,
                    hasContent: true
                ) == "Garden / 調査"
            )
        }
        let teamDestinations = [
            ComposerDestinationLabel.teamDestination(
                action: AgoraComposerRouting.action(phase: .discussing, canStartDiscussion: true, text: ""),
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            ),
            ComposerDestinationLabel.teamDestination(
                action: AgoraComposerRouting.action(phase: .idle, canStartDiscussion: true, text: ""),
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            ),
            ComposerDestinationLabel.teamDestination(
                action: AgoraComposerRouting.action(phase: .idle, canStartDiscussion: false, text: ""),
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            ),
        ]
        #expect(
            ComposerDestinationLabel.text(
                for: teamDestinations[0],
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: teamDestinations[1],
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: teamDestinations[2],
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: .conversation(projectName: "Phlox", taskName: "入力欄改善"),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 入力欄改善"
        )
    }

    @Test("teamDestination は conversation を返さない")
    func teamDestinationNeverReturnsConversation() {
        let actions: [AgoraComposerAction] = [
            .startDiscussion(agenda: "議題"),
            .discussionUtterance("発言"),
            .legacyRootSend("本文"),
        ]
        for action in actions {
            let destination = ComposerDestinationLabel.teamDestination(
                action: action,
                rootProjectName: "Phlox",
                rootTaskName: "全体作業"
            )
            let label = ComposerDestinationLabel.text(
                for: destination,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            )
            #expect(label != "Phlox / 全体作業")
            #expect(!label.hasPrefix("Phlox / 全体作業") || label.contains("親セッションへの送信"))
        }
        #expect(
            ComposerDestinationLabel.text(
                for: ComposerDestinationLabel.teamDestination(
                    action: .startDiscussion(agenda: "議題"),
                    rootProjectName: "Phlox",
                    rootTaskName: "全体作業"
                ),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論を開始"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: ComposerDestinationLabel.teamDestination(
                    action: .discussionUtterance("発言"),
                    rootProjectName: "Phlox",
                    rootTaskName: "全体作業"
                ),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
        #expect(
            ComposerDestinationLabel.text(
                for: ComposerDestinationLabel.teamDestination(
                    action: .legacyRootSend("本文"),
                    rootProjectName: "Phlox",
                    rootTaskName: "全体作業"
                ),
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "Phlox / 全体作業 — 親セッションへの送信"
        )
    }

    @Test("討論中は根がなくても送信不可（送信先がありません）を付けない")
    func discussingWithoutRootIsNotMissingDestination() {
        #expect(
            composedLabel(
                phase: .discussing,
                canStartDiscussion: true,
                rootProjectName: nil,
                rootTaskName: nil,
                hasDestination: true,
                isReadyForInput: true,
                hasContent: true
            ) == "討論への発言"
        )
    }
}
