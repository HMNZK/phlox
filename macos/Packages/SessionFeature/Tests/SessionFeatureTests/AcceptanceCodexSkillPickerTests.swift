import Foundation
import Observation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
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
            #expect(response.data.first?.skills.map(\.name) == ["日本語レビュー", "disabled"])
            #expect(response.data.first?.skills.map(\.path) == ["/workspace/skills/review", "/disabled"])
            #expect(response.data.first?.skills.last?.enabled == false)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("選択送信はnative skill input一件で$nameをwire textへ重複しない")
    func sendUsesOneNativeSkillInputWithoutDuplicateText() async throws {
        let transport = CodexPlanSkillFakeTransport()
        let client = CodexAppServerClient(transport: transport)
        do {
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
        } catch {
            await client.close()
            throw error
        }
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
        do {
            await client.start()
            let state = CodexSkillSelectionState(client: client, sessionCWD: cwd)
            await state.refresh()
            let old = try #require(state.skills.first)
            #expect(state.select(old))
            state.invalidate()
            #expect(state.select(old) == false)
            #expect(state.inputs(for: "$review 本文") == nil)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }

    @Test("skills/changed は実 transport から VM へ届き、自動再取得・エラー・再選択を反映する")
    @MainActor
    func changedReloadsThroughViewModelAndRequiresReselection() async throws {
        let transport = CodexProductionTransport(
            cwd: cwd,
            skillListResponses: [
                skillListResponseJSON(path: "/old/review", cwd: cwd),
                skillListResponseJSON(
                    path: "/new/review",
                    cwd: cwd,
                    errors: [("skill scan failed", "/new/review")]
                ),
                skillListResponseJSON(path: "/fresh/review", cwd: cwd),
            ]
        )
        let appServer = CodexAppServerClient(transport: transport)
        let client = CodexStructuredAgentClient(client: appServer)
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: cwd
        )
        do {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            let state = try #require(viewModel.codexSkillSelectionState)
            try await waitUntil("initial skills/list") {
                state.skills.first?.path == "/old/review"
            }
            #expect(state.select(name: "review", path: "/old/review"))
            #expect(state.inputs(for: "$review 本文") == [
                .text("本文"),
                .skill(name: "review", path: "/old/review"),
            ])

            // state.handle(.skillsChanged) を直接呼ばず、app-server transport の JSON-RPC 通知から投入する。
            transport.receive(#"{"jsonrpc":"2.0","method":"skills/changed","params":{}}"#)
            try await waitUntil("skills/changed の自動再取得とエラー反映") {
                state.skills.first?.path == "/new/review" && state.errorMessage == "skill scan failed"
            }
            #expect(await transport.methods().filter { $0 == "skills/list" }.count == 2)
            #expect(state.isStale)
            #expect(state.requiresReselection)
            #expect(state.inputs(for: "$review 本文") == nil)
            #expect(state.select(name: "review", path: "/new/review") == false)
            #expect(state.invalidSelectionMessage?.contains("再選択") == true)

            // エラー後の再取得が成功しても、旧 identity は自動採用せず、明示的な再選択を要求する。
            transport.receive(#"{"jsonrpc":"2.0","method":"skills/changed","params":{}}"#)
            try await waitUntil("エラー後の skills/list 再取得") {
                state.skills.first?.path == "/fresh/review" && state.errorMessage == nil
            }
            #expect(state.requiresReselection)
            #expect(state.inputs(for: "$review 本文") == nil)
            #expect(state.select(name: "review", path: "/fresh/review"))
            #expect(state.inputs(for: "$review 本文") == [
                .text("本文"),
                .skill(name: "review", path: "/fresh/review"),
            ])
            #expect(await transport.methods().filter { $0 == "skills/list" }.count == 3)
        } catch {
            await viewModel.terminate()
            await client.close()
            throw error
        }
        await viewModel.terminate()
        await client.close()
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        guard condition() == false else { return }
        let waiter = SkillPickerObservationWaiter(condition: condition)
        let fulfilled = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await waiter.wait() }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return false
                } catch {
                    return false
                }
            }
            let result = await group.next() ?? false
            group.cancelAll()
            waiter.cancel()
            await group.waitForAll()
            return result
        }
        guard fulfilled else {
            throw SkillPickerWaitError.timedOut(description)
        }
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

private func skillListResponseJSON(
    path: String,
    cwd: String,
    errors: [(message: String, path: String)] = []
) -> JSONValue {
    .object([
        "data": .array([.object([
            "cwd": .string(cwd),
            "errors": .array(errors.map { .object([
                "message": .string($0.message),
                "path": .string($0.path),
            ]) }),
            "skills": .array([.object([
                "description": .string(""),
                "enabled": .bool(true),
                "name": .string("review"),
                "path": .string(path),
                "scope": .string("user"),
            ])]),
        ])]),
    ])
}

private enum SkillPickerWaitError: Error, CustomStringConvertible {
    case timedOut(String)

    var description: String {
        switch self {
        case .timedOut(let description): "Timed out waiting for \(description)"
        }
    }
}

@MainActor
private final class SkillPickerObservationWaiter {
    private let condition: @MainActor () -> Bool
    private let signals: AsyncStream<Void>
    private let signalContinuation: AsyncStream<Void>.Continuation
    private var cancelled = false

    init(condition: @escaping @MainActor () -> Bool) {
        self.condition = condition
        var captured: AsyncStream<Void>.Continuation?
        signals = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { captured = $0 }
        signalContinuation = captured!
    }

    func wait() async -> Bool {
        guard !condition() else { return true }
        arm()
        for await _ in signals {
            guard !cancelled else { return false }
            if condition() { return true }
            arm()
        }
        return !cancelled && condition()
    }

    func cancel() {
        cancelled = true
        signalContinuation.finish()
    }

    private func arm() {
        withObservationTracking {
            _ = condition()
        } onChange: { [self] in
            Task { @MainActor [self] in
                signalContinuation.yield()
            }
        }
    }
}
