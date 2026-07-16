import Foundation
import Testing
import AgentDomain
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-3 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-3.md — sessionNode(id:) / sessionForest(in:) のセマンティクス完全同値の凍結。
// このタスクは性能改善（Dictionary インデックス・forest キャッシュ）であり、
// 本テストは「最適化後も挙動が1ビットも変わらない」ことを固定する（着手時点で green が正しい）。

private func pm3Task3Flatten(_ nodes: [SessionTreeNode]) -> [SessionID] {
    nodes.flatMap { [$0.id] + pm3Task3Flatten($0.children) }
}

@Suite(.serialized)
struct PM3Task3SidebarIndexAcceptanceTests {

    // sessionNode(id:) は追加・改名・削除のどの変更後も「配列の線形検索」と同じ結果を返し続ける。
    @Test @MainActor
    func sessionNodeLookup_staysConsistentThroughMutations() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let a = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let b = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let c = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, from: a, launchContext: .orchestration)

        func assertConsistent(_ context: String) {
            for id in [a, b, c] {
                let viaLookup = dashboard.sessionNode(id: id)?.id
                let viaLinear = dashboard.sessionNodes.first { $0.id == id }?.id
                #expect(viaLookup == viaLinear, "\(context): sessionNode(id:) と線形検索が不一致 (id=\(id))")
            }
        }

        assertConsistent("spawn 直後")
        #expect(dashboard.sessionNode(id: a) != nil)
        #expect(dashboard.sessionNode(id: c) != nil, "orchestration 子も引けること")
        #expect(dashboard.sessionNode(id: SessionID()) == nil, "存在しない ID は nil")

        dashboard.renameSession(a, to: "renamed-a")
        assertConsistent("rename 後")
        #expect(dashboard.sessionNode(id: a)?.controllable.name == "renamed-a")

        await dashboard.removeSession(b)
        #expect(dashboard.sessionNode(id: b) == nil, "削除済みセッションが引ける（インデックス無効化漏れ）")
        assertConsistent("remove 後")

        let d = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        #expect(dashboard.sessionNode(id: d) != nil, "削除後の新規 spawn が引けない（インデックス無効化漏れ）")
        assertConsistent("再 spawn 後")
    }

    // sessionForest(in:) は sessionNodes の変更（追加・親子・削除・改名）を正しく反映し続ける。
    // 可視フィルタ（orchestration 子はサイドバー非表示）のセマンティクスも不変。
    @Test @MainActor
    func sessionForest_reflectsMutationsAndKeepsVisibilitySemantics() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let parent = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let child = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, from: parent)
        let orchestrationRoot = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, launchContext: .orchestration
        )

        var forest = dashboard.sessionForest(in: projectID)
        var flattened = pm3Task3Flatten(forest)
        #expect(flattened.contains(parent))
        #expect(flattened.contains(child), "子セッションが forest に現れない")
        #expect(!forest.map(\.id).contains(orchestrationRoot), "orchestration ルートがサイドバー forest に露出（可視フィルタ変化）")
        let parentNode = try #require(forest.first { $0.id == parent })
        #expect(parentNode.children.map(\.id).contains(child), "親子構造が forest に反映されていない")

        // 変更1: 改名が forest の name に反映される。
        dashboard.renameSession(parent, to: "renamed-parent")
        forest = dashboard.sessionForest(in: projectID)
        #expect(forest.first { $0.id == parent }?.name == "renamed-parent", "rename が forest に反映されない（キャッシュ無効化漏れ）")

        // 変更2: 子の削除が forest から消える。
        await dashboard.removeSession(child)
        forest = dashboard.sessionForest(in: projectID)
        flattened = pm3Task3Flatten(forest)
        #expect(!flattened.contains(child), "削除した子が forest に残存（キャッシュ無効化漏れ）")

        // 変更3: 新規 spawn が forest に現れる。
        let e = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        forest = dashboard.sessionForest(in: projectID)
        #expect(pm3Task3Flatten(forest).contains(e), "新規 spawn が forest に現れない（キャッシュ無効化漏れ）")

        // 別プロジェクトの forest は影響を受けない（プロジェクト絞り込み不変）。
        let otherProject = ProjectID()
        #expect(dashboard.sessionForest(in: otherProject).isEmpty)
    }
}
