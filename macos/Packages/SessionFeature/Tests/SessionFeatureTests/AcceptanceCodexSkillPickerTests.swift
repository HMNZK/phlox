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
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}
