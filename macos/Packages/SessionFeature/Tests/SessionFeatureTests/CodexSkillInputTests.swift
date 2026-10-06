import Testing
import CodexAppServerKit
@testable import SessionFeature

/// skills/list DTO・typed event・native skill input を固定する。
@Suite("Codex skill input")
struct CodexSkillInputTests {
    private let cwd = "/contract/作業"

    @Test("skills/list request は session cwd 一件を送り、実responseを受け取る")
    func requestCWDIsExactAndSingle() async throws {
        let responseJSON: JSONValue = .object([
            "data": .array([.object([
                "cwd": .string(cwd),
                "errors": .array([]),
                "skills": .array([
                    .object([
                        "description": .string("契約"),
                        "enabled": .bool(true),
                        "name": .string("review"),
                        "path": .string("/contract/skills/review"),
                        "scope": .string("user"),
                    ]),
                ]),
            ])]),
        ])
        let transport = CodexPlanSkillFakeTransport(skillsListResult: responseJSON)
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()

            let response = try await client.skillsList(SkillsListParams(cwds: [cwd], forceReload: true))
            let request = try #require(await transport.firstRequest(method: "skills/list"))
            #expect(request["method"] == .string("skills/list"))
            #expect(request["params"] == .object([
                "cwds": .array([.string(cwd)]),
                "forceReload": .bool(true),
            ]))
            #expect(response.data.first?.cwd == cwd)
            #expect(response.data.first?.skills.first?.path == "/contract/skills/review")
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("skills/changed は実 JSON-RPC 通知から typed ThreadEvent になる")
    func changedEventIsTyped() async throws {
        let event = try await receiveCodexThreadEvent(
            method: "skills/changed",
            params: .object([:])
        )
        guard case .skillsChanged? = event else {
            Issue.record("skills/changed が .skillsChanged になっていない")
            return
        }
    }

    @Test("turn/start は text と native skill input を重複させない")
    func nativeSkillInputIsOneAndNotText() async throws {
        let transport = CodexPlanSkillFakeTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
            await client.start()
            _ = try await client.turnStart(TurnStartParams(
                threadId: "thread-skill",
                input: [
                    .text("質問本文"),
                    .skill(name: "review", path: "/contract/skills/review"),
                ]
            ))

            let request = try #require(await transport.firstRequest(method: "turn/start"))
            let raw = try #require(request["params"]?["input"])
            #expect(raw.arrayValue?.filter { $0["type"] == .string("skill") }.count == 1)
            #expect(raw.arrayValue?.contains {
                $0["type"] == .string("text") && $0["text"] == .string("$review")
            } == false)
            #expect(raw.arrayValue?.contains {
                $0["name"] == .string("review") && $0["path"] == .string("/contract/skills/review")
            } == true)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}
