import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex 履歴")
struct AcceptanceCodexHistoryTests {
    private let cwd = "/tmp/phlox-codex-history"

    private func summary(
        _ id: String,
        source: ThreadSessionSource = .appServer,
        parent: String? = nil,
        directInput: Bool? = nil
    ) -> ThreadSummary {
        ThreadSummary(
            id: id,
            cliVersion: "0.147.0",
            createdAt: 1,
            cwd: cwd,
            ephemeral: false,
            modelProvider: "openai",
            preview: id,
            sessionId: "session-\(id)",
            source: source,
            status: .idle,
            turns: [],
            updatedAt: 2,
            parentThreadId: parent,
            canAcceptDirectInput: directInput
        )
    }

    @Test("thread/list は cwd と3 sourceを wire へ保持する")
    func listRequestPreservesHistoryFilters() throws {
        let params = ThreadListParams(
            cwd: .multiple([cwd]),
            sourceKinds: [.cli, .vscode, .appServer],
            parentThreadId: nil,
            ancestorThreadId: nil
        )
        let raw = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(params)
        )

        #expect(raw["cwd"] == JSONValue.array([JSONValue.string(cwd)]))
        #expect(raw["sourceKinds"] == JSONValue.array([
            JSONValue.string("cli"), JSONValue.string("vscode"), JSONValue.string("appServer"),
        ]))
        #expect(raw["parentThreadId"] == nil)
        #expect(raw["ancestorThreadId"] == nil)
    }

    @Test("subAgent/parent/direct-input identity は実 ThreadSummary から失わない")
    func childIdentityIsAvailableToHistoryConsumer() throws {
        let child = summary("child", source: .subAgent(.object(["parentThreadId": .string("main")])), parent: "main", directInput: false)
        let decoded = try JSONDecoder().decode(
            ThreadSummary.self,
            from: JSONEncoder().encode(child)
        )

        #expect(decoded.id == "child")
        #expect(decoded.parentThreadId == "main")
        #expect(decoded.canAcceptDirectInput == false)
        #expect(decoded.source == child.source)
    }

    @Test("thread/read は includeTurns=true、resume は選択IDを wire へ渡す")
    func readAndResumeRequestsHaveExactIdentity() throws {
        let read = ThreadReadParams(threadId: "selected", includeTurns: true)
        let resume = ThreadResumeParams(threadId: "selected", cwd: cwd)
        let readRaw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(read))
        let resumeRaw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(resume))

        #expect(readRaw == JSONValue.object([
            "threadId": .string("selected"), "includeTurns": .bool(true),
        ]))
        #expect(resumeRaw["threadId"] == JSONValue.string("selected"))
        #expect(resumeRaw["cwd"] == JSONValue.string(cwd))
    }

    @Test("CodexSessionHistory は ID を保ったまま全ページを一覧へ反映する")
    @MainActor
    func concreteHistoryKeepsDistinctThreadIDs() async throws {
        let transport = CodexHistoryTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()

        let history = CodexSessionHistory(client: client, cwd: cwd)
        await history.refresh()

        #expect(history.threads.map(\.id) == ["cli-1", "app-1", "app-2"])
        #expect(history.threads.map(\.preview) == ["shared title", "shared title", "shared title"])
        await client.close()
    }
}
