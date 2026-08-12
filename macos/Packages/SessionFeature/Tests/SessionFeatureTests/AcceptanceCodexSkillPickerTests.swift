import Foundation
import Testing
import CodexAppServerKit
@testable import SessionFeature

@Suite("Acceptance: Codex /skill picker")
struct AcceptanceCodexSkillPickerTests {
    private let cwd = "/workspace/プロジェクト"

    @Test("skills/list は現在のsession cwdだけをwireへ送り、実responseをdecodeする")
    func listUsesExactSessionCWD() async throws {
        let result: JSONValue = .object([
            "data": .array([.object([
                "cwd": .string(cwd),
                "errors": .array([]),
                "skills": .array([
                    .object([
                        "description": .string("説明"),
                        "enabled": .bool(true),
                        "name": .string("日本語レビュー"),
                        "path": .string("/workspace/skills/review"),
                        "scope": .string("user"),
                    ]),
                    .object([
                        "description": .string("説明"),
                        "enabled": .bool(false),
                        "name": .string("disabled"),
                        "path": .string("/disabled"),
                        "scope": .string("user"),
                    ]),
                ]),
            ])]),
        ])
        let transport = CodexPlanSkillFakeTransport(skillsListResult: result)
        let client = CodexAppServerClient(transport: transport)
        await client.start()

        let response = try await client.skillsList(SkillsListParams(cwds: [cwd], forceReload: true))
        let request = try #require(await transport.firstRequest(method: "skills/list"))
        #expect(request["method"] == .string("skills/list"))
        #expect(request["params"] == .object([
            "cwds": .array([.string(cwd)]),
            "forceReload": .bool(true),
        ]))
        #expect(response.data.first?.cwd == cwd)
        #expect(response.data.first?.skills.map(\.name) == ["日本語レビュー", "disabled"])
        #expect(response.data.first?.skills.map(\.path) == ["/workspace/skills/review", "/disabled"])
        #expect(response.data.first?.skills.last?.enabled == false)
        await client.close()
    }

    @Test("選択送信はnative skill input一件で$nameをwire textへ重複しない")
    func sendUsesOneNativeSkillInputWithoutDuplicateText() async throws {
        let transport = CodexPlanSkillFakeTransport()
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        _ = try await client.turnStart(TurnStartParams(
            threadId: "thread-skill",
            input: [.text("質問本文"), .skill(name: "review", path: "/skills/review")]
        ))
        let request = try #require(await transport.firstRequest(method: "turn/start"))
        let raw = try #require(request["params"]?["input"])
        #expect(raw.arrayValue?.filter { $0["type"] == .string("skill") }.count == 1)
        #expect(raw.arrayValue?.contains { $0["type"] == .string("text") && $0["text"] == .string("$review") } == false)
        #expect(raw.arrayValue?.contains { $0["name"] == .string("review") && $0["path"] == .string("/skills/review") } == true)
        await client.close()
    }

    @Test("skills/changed は実 JSON-RPC 通知から client.events の typed event へ到達する")
    func changedNotificationIsTyped() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "skills/changed",
            params: .object([:])
        )
        guard case .skillsChanged? = event else {
            Issue.record("skills/changed が CodexAppServerClient.events の .skillsChanged になっていない")
            return
        }
    }

    @Test("実 state は identity・検索・disabled/invalid を保持し、fresh 選択を native input にする")
    @MainActor
    func stateFiltersAndBuildsNativeInput() async throws {
        let result: JSONValue = .object([
            "data": .array([.object([
                "cwd": .string(cwd),
                "errors": .array([]),
                "skills": .array([
                    .object(["description": .string(""), "enabled": .bool(true), "name": .string("レビュー"), "path": .string("/one"), "scope": .string("user")]),
                    .object(["description": .string(""), "enabled": .bool(true), "name": .string("レビュー"), "path": .string("/one"), "scope": .string("user")]),
                    .object(["description": .string(""), "enabled": .bool(true), "name": .string("レビュー"), "path": .string("/two"), "scope": .string("user")]),
                    .object(["description": .string(""), "enabled": .bool(false), "name": .string("無効"), "path": .string("/disabled"), "scope": .string("user")]),
                    .object(["description": .string(""), "enabled": .bool(true), "name": .string(""), "path": .string("/invalid"), "scope": .string("user")]),
                ]),
            ])]),
        ])
        let transport = CodexPlanSkillFakeTransport(skillsListResult: result)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        let state = CodexSkillSelectionState(client: client, sessionCWD: cwd)
        await state.refresh()

        #expect(state.skills.count == 4)
        state.search("レビュー")
        #expect(state.filteredSkills.map(\.path) == ["/one", "/two"])
        #expect(state.select(name: "無効", path: "/disabled") == false)
        #expect(state.select(name: "レビュー", path: "/two"))
        #expect(state.inputs(for: "本文 $レビュー 後 $レビュー") == [
            .text("本文  後"),
            .skill(name: "レビュー", path: "/two"),
        ])
        await client.close()
    }

    @Test("実 state は changed 後に旧選択を再採用せず、stale input を送らない")
    @MainActor
    func stateRejectsStaleSelection() async throws {
        let result: JSONValue = .object([
            "data": .array([.object([
                "cwd": .string(cwd), "errors": .array([]), "skills": .array([
                    .object(["description": .string(""), "enabled": .bool(true), "name": .string("review"), "path": .string("/review"), "scope": .string("user")]),
                ]),
            ])]),
        ])
        let transport = CodexPlanSkillFakeTransport(skillsListResult: result)
        let client = CodexAppServerClient(transport: transport)
        await client.start()
        let state = CodexSkillSelectionState(client: client, sessionCWD: cwd)
        await state.refresh()
        let old = try #require(state.skills.first)
        #expect(state.select(old))
        state.invalidate()
        #expect(state.select(old) == false)
        #expect(state.inputs(for: "$review 本文") == nil)
        await client.close()
    }

    @Test("skills/changed は一覧を自動再取得し、旧選択の再送を止める")
    @MainActor
    func changedReloadsAndRequiresReselection() async throws {
        let client = ReloadingSkillClient(responses: [
            skillListResponse(path: "/old/review", cwd: cwd),
            skillListResponse(path: "/new/review", cwd: cwd),
        ])
        let state = CodexSkillSelectionState(client: client, sessionCWD: cwd)
        await state.refresh()
        let old = try #require(state.skills.first)
        #expect(state.select(old))

        state.handle(.skillsChanged)
        #expect(state.isStale || state.isLoading)

        for _ in 0..<100 {
            if await client.callCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await client.callCount == 2)
        #expect(state.skills.first?.path == "/new/review")
        #expect(state.requiresReselection)
        #expect(state.inputs(for: "$review 本文") == nil)
        #expect(state.invalidSelectionMessage?.contains("再選択") == true)

        #expect(state.select(name: "review", path: "/new/review"))
        #expect(state.inputs(for: "$review 本文") == [
            .text("本文"),
            .skill(name: "review", path: "/new/review"),
        ])
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}

private func skillListResponse(path: String, cwd: String) -> SkillsListResponse {
    SkillsListResponse(data: [SkillsListEntry(
        cwd: cwd,
        errors: [],
        skills: [SkillMetadata(
            description: "",
            enabled: true,
            name: "review",
            path: path,
            scope: .user
        )]
    )])
}

private final class ReloadingSkillClient: CodexSkillSelectionClient, @unchecked Sendable {
    let skillEvents = AsyncStream<ThreadEvent> { continuation in
        continuation.finish()
    }

    private actor CallState {
        var responses: [SkillsListResponse]
        var calls = 0

        init(responses: [SkillsListResponse]) {
            self.responses = responses
        }

        func next() -> SkillsListResponse {
            let response = responses[min(calls, responses.count - 1)]
            calls += 1
            return response
        }
    }

    private let state: CallState

    init(responses: [SkillsListResponse]) {
        state = CallState(responses: responses)
    }

    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        await state.next()
    }

    var callCount: Int {
        get async { await state.calls }
    }
}
