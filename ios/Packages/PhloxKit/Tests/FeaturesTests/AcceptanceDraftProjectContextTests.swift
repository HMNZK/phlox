import Foundation
import Testing
import PhloxCore
import Features

/// task-2 受け入れテスト（PM 著・凍結。アサーションの変更は禁止。ハーネス欠陥を
/// 発見した場合は PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
///
/// バグ2件を同時に凍結する（どちらも「下書きが ID と表示名を 1 本の String に押し込んでいた」ことが原因）:
///  (a) プロジェクトを選んで作ったセッションが macOS の「その他」に落ちる
///      → 下書きの `projectID` が `SpawnRequest.projectID` として送られること
///  (b) 作成画面の文脈ラベルに UUID が出る
///      → `inputContextDisplayName` が**表示名**を返すこと
///
/// 契約: tasks/wire-contract.md §3。
@MainActor
struct AcceptanceDraftProjectContextTests {
    private let projectUUID = "6C2F0E2A-1111-4222-8333-444455556666"

    /// 下書き画面の placeholder を production（DraftSessionComposeDestination）と同型で作る。
    private func makeDraftPlaceholderSession() -> Session {
        Session(
            id: "draft-compose",
            name: "Gardenia",
            agent: .codex,
            status: .running,
            subtitle: "Gardenia",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("下書きの文脈ラベルはプロジェクト名を出す（UUID を出さない）")
    func draftContextLabelShowsProjectName() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeDraftPlaceholderSession(), api: api)

        await vm.prepareDraft(SessionComposeDraft(project: "Gardenia", projectID: projectUUID))

        #expect(vm.isAwaitingInitialSpawn, "下書き未 spawn 状態であること（前提）")
        #expect(vm.inputContextDisplayName == "Gardenia")
    }

    @Test("下書きの projectID が spawn リクエストへ渡る")
    func draftProjectIDReachesSpawnRequest() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeDraftPlaceholderSession(), api: api)

        await vm.prepareDraft(SessionComposeDraft(project: "Gardenia", projectID: projectUUID))
        vm.inputText = "はじめまして"
        await vm.sendMessage()

        let spawnRequest = await api.lastSpawnRequest
        #expect(spawnRequest?.projectID == projectUUID)
    }

    @Test("プロジェクト未所属（「その他」）の下書きは projectID を送らない")
    func unassignedDraftSendsNoProjectID() async throws {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeDraftPlaceholderSession(), api: api)

        await vm.prepareDraft(SessionComposeDraft(project: "その他", projectID: nil))
        vm.inputText = "はじめまして"
        await vm.sendMessage()

        // spawn 自体が起きていない実装でも `spawnRequest?.projectID == nil` は通ってしまうため、
        // 先に spawn が呼ばれたことを前提として固定する（空振り合格の防止）。
        let spawnRequest = try #require(await api.lastSpawnRequest, "spawn が呼ばれていること")
        #expect(spawnRequest.projectID == nil)
    }

    @Test("プロジェクトを持つセッションでは従来どおりサーバ由来の projectName を出す")
    func realSessionKeepsServerProjectName() {
        let api = MockAPI()
        let session = Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .idle,
            needsAttention: false,
            subtitle: "proj",
            projectId: projectUUID,
            projectName: "Gardenia",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let vm = SessionDetailViewModel(session: session, api: api)

        #expect(vm.inputContextDisplayName == "Gardenia")
    }
}
