import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite("チャットカード: 担当表示と変更行数") @MainActor
struct ChatCardRefinementAcceptanceTests {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = SessionID()
    private let executionID = UUID()

    @Test("サブエージェントは実行中も完了後も、説明に加えて担当と状態を表示する")
    func subAgentTextIdentifiesOwnerAndState() {
        let running = AgentStatusAction.Label.subAgent(description: "依存関係を調査", type: "Explore", status: .running)
            .text(running: true, locale: Locale(identifier: "ja"))
        let completed = AgentStatusAction.Label.subAgent(description: "依存関係を調査", type: "Explore", status: .completed)
            .text(running: false, locale: Locale(identifier: "ja"))

        #expect(running.contains("サブエージェント"))
        #expect(running.contains("依存関係を調査"))
        #expect(running.contains("実行中"))
        #expect(completed.contains("サブエージェント"))
        #expect(completed.contains("完了"))
    }

    @Test("子の失敗・停止を実行中と表示せず、親のファイル編集を子と表示しない")
    func subAgentTerminalStatesStayDistinctFromParentWork() {
        let failed = AgentStatusAction.Label.subAgent(description: "参照確認", type: "Explore", status: .failed)
            .text(running: false, locale: Locale(identifier: "ja"))
        let stopped = AgentStatusAction.Label.subAgent(description: "参照確認", type: "Explore", status: .stopped)
            .text(running: false, locale: Locale(identifier: "ja"))
        let parent = AgentStatusAction.Label.edit(file: "Card.swift")
            .text(running: true, locale: Locale(identifier: "ja"))

        #expect(failed.contains("失敗"))
        #expect(stopped.contains("停止"))
        #expect(!failed.contains("実行中"))
        #expect(!parent.contains("サブエージェント"))
        #expect(parent == "Card.swift を編集中")
    }

    @Test("変更詳細を未取得でも、カード全体の追加・削除行数を要約に含める")
    func summaryCountsUnloadedChangesAndExcludesOtherTurns() async throws {
        let edits = (0..<40).map { index in
            file("file-\(index)", path: "/workspace/File\(index).swift",
                diff: "--- a/file\n+++ b/file\n@@ -1 +1,2 @@\n-old\n+new\n+extra\n context", completed: true)
        }
        let items: [ChatItem] = [
            input("previous"), file("previous-edit", path: "/workspace/Other.swift", diff: "+previous", completed: true),
            input("current"),
        ] + edits
        let store = RuntimeChatReadIndexStore()

        let cards = try await summaries(store, items: items, revision: 1)
        let previous = try #require(cards.first { $0.inputID == "previous" })
        let current = try #require(cards.first { $0.inputID == "current" })

        #expect(try counts(previous) == ["additions": 1, "deletions": 0])
        #expect(try counts(current) == ["additions": 80, "deletions": 40])
    }

    @Test("先行表示は未確定として扱い、同じ作業IDの確定と再受信で二重加算しない")
    func provisionalEditIsReplacedByConfirmedDiff() async throws {
        let store = RuntimeChatReadIndexStore()
        let pending = [input("current"), file("edit", path: "/workspace/Card.swift", diff: "", completed: false)]
        let first = try #require(try await summaries(store, items: pending, revision: 1).first)
        #expect(try counts(first) == nil)
        let completed = [input("current"), file("edit", path: "/workspace/Card.swift",
            diff: "@@\n-before\n+after\n+extra", completed: true)]
        store.invalidate(from: 1, itemIDs: ["edit"])

        let second = try #require(try await summaries(store, items: completed, revision: 2).first)
        let repeated = try #require(try await summaries(store, items: completed, revision: 2).first)

        #expect(try counts(second) == ["additions": 2, "deletions": 1])
        #expect(try counts(repeated) == ["additions": 2, "deletions": 1])
    }

    @Test("別操作の再編集は加算し、同じ作業IDの差分修正は古い値を置き換える")
    func changedDiffReplacesItsContribution() async throws {
        let store = RuntimeChatReadIndexStore()
        let initial = [input("current"),
            file("edit-1", path: "/workspace/Card.swift", diff: "+first", completed: true),
            file("edit-2", path: "/workspace/Card.swift", diff: "-old\n+next", completed: true)]
        _ = try await summaries(store, items: initial, revision: 1)
        let changed = [input("current"),
            file("edit-1", path: "/workspace/Card.swift", diff: "+first\n+second\n+third", completed: true),
            file("edit-2", path: "/workspace/Card.swift", diff: "-old\n+next", completed: true)]
        store.invalidate(from: 1, itemIDs: ["edit-1"])

        let summary = try #require(try await summaries(store, items: changed, revision: 2).first)

        #expect(try counts(summary) == ["additions": 4, "deletions": 1])
    }

    private func input(_ id: String) -> ChatItem {
        .userMessage(id: id, text: "表示を直す", timestamp: time, attachments: [])
    }

    private func file(_ id: String, path: String, diff: String, completed: Bool) -> ChatItem {
        .fileChange(id: id, changes: [.init(path: path, diff: diff, kind: "edit")],
            timestamp: time.addingTimeInterval(1), completedAt: completed ? time.addingTimeInterval(2) : nil)
    }

    private func summaries(_ store: RuntimeChatReadIndexStore, items: [ChatItem], revision: Int) async throws
        -> [SessionRuntimeCardSummary] {
        let response = try await store.response(items: items, executionID: executionID, revision: revision,
            liveState: .init(isProcessing: true, activityState: .editing, hangAssessment: nil, isAwaitingReply: false),
            usesCards: true, request: .init(sessionID: sessionID, executionID: executionID, target: .chatReadTail),
            usage: [:])
        guard case .chatReadPage(let page) = response else {
            Issue.record("カードの読み取り応答が必要")
            return []
        }
        return page.blocks.compactMap { if case .card(let card) = $0.content { card } else { nil } }
    }

    private func counts(_ card: SessionRuntimeCardSummary) throws -> [String: Int]? {
        // 実行サービスの利用者が受け取るJSON契約。未実装でもコンパイル可能にしてREDを確かめる。
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        return json?["changeCounts"] as? [String: Int]
    }
}
