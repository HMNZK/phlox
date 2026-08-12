import Foundation
import Observation
import Testing
import SwiftUI
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// task-6/task-9 の統合受け入れテスト。
///
/// 既存の View を直接検査せず、Codex の structured client と
/// `ChatSessionViewModel` を実際に合成して、同じ入力が transcript・履歴・
/// task/background/sub-agent の各 surface へ届く境界を固定する。
/// UI E2E は Phase 4 の担当範囲なので、このファイルでは扱わない。
@Suite("AcceptanceCodexChatParityIntegrationTests")
@MainActor
struct AcceptanceCodexChatParityIntegrationTests {
    private final class RecordingClient: StructuredAgentClient, @unchecked Sendable {
        private actor Recorder {
            private var inputs: [[ChatInput]] = []
            private var resumes: [String] = []
            private var interruptCount = 0

            func recordInputs(_ input: [ChatInput]) {
                inputs.append(input)
            }

            func recordResume(_ sessionRef: String) {
                resumes.append(sessionRef)
            }

            func recordInterrupt() {
                interruptCount += 1
            }

            var inputSnapshot: [[ChatInput]] { inputs }
            var resumeSnapshot: [String] { resumes }
            var interruptSnapshot: Int { interruptCount }
        }

        let events: AsyncStream<NormalizedChatEvent>
        private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
        private let recorder = Recorder()

        init() {
            var captured: AsyncStream<NormalizedChatEvent>.Continuation?
            events = AsyncStream { captured = $0 }
            continuation = captured!
        }

        func start() async {}

        func turnStart(_ input: [ChatInput]) async throws {
            await recorder.recordInputs(input)
        }

        func resume(sessionRef: String) async throws {
            await recorder.recordResume(sessionRef)
        }

        func interrupt() async throws {
            await recorder.recordInterrupt()
        }

        func close() async {
            continuation.finish()
        }

        func yield(_ event: NormalizedChatEvent) {
            continuation.yield(event)
        }

        var inputs: [[ChatInput]] { get async { await recorder.inputSnapshot } }
        var resumes: [String] { get async { await recorder.resumeSnapshot } }
        var interruptCount: Int { get async { await recorder.interruptSnapshot } }
    }

    /// app-server の実 transport → client → structured adapter → VM を通す画像検査用。
    /// 画像を通常 text へ丸める現在の adapter は、指定 assertion で red になる。
    private final class JSONRPCTransport: AppServerTransport, @unchecked Sendable {
        private actor Recorder {
            private var messages: [JSONValue] = []

            func record(_ message: JSONValue) {
                messages.append(message)
            }

            var snapshot: [JSONValue] { messages }
        }

        let receivedLines: AsyncStream<Data>
        private let continuation: AsyncStream<Data>.Continuation
        private let recorder = Recorder()

        init() {
            var captured: AsyncStream<Data>.Continuation?
            receivedLines = AsyncStream { captured = $0 }
            continuation = captured!
        }

        func send(_ data: Data) async throws {
            let line = data.firstIndex(of: 0x0A).map { Data(data[..<$0]) } ?? data
            let request = try JSONDecoder().decode(JSONValue.self, from: line)
            await recorder.record(request)

            guard let id = request["id"]?.intValue,
                  let method = request["method"]?.stringValue else {
                return
            }

            let result: JSONValue
            switch method {
            case "initialize":
                result = .object([
                    "codexHome": .string("/tmp/codex-home"),
                    "platformFamily": .string("macOS"),
                    "platformOs": .string("macOS"),
                    "userAgent": .string("codex-integration-test"),
                ])
            case "thread/start", "thread/resume":
                result = .object([
                    "thread": .object([
                        "id": .string("codex-integration-thread"),
                        "status": .object(["type": .string("idle")]),
                    ]),
                ])
            case "model/list":
                // 画像送信の fixture は、実際に画像 modality を広告する model を
                // 選択可能な状態にしてから turn/start へ進める。
                result = .object(["data": .array([.object([
                    "id": .string("gpt-5-codex"),
                    "model": .string("gpt-5-codex"),
                    "displayName": .string("GPT-5 Codex"),
                    "description": .string(""),
                    "hidden": .bool(false),
                    "supportedReasoningEfforts": .array([.string("medium")]),
                    "defaultReasoningEffort": .string("medium"),
                    "isDefault": .bool(true),
                    "inputModalities": .array([.string("text"), .string("image")]),
                ])])])
            case "skills/list":
                result = .object(["data": .array([.object([
                    "cwd": .string("/tmp/phlox-codex-parity"),
                    "errors": .array([]),
                    "skills": .array([
                        .object([
                            "description": .string("レビューを実行"),
                            "enabled": .bool(true),
                            "name": .string("review"),
                            "path": .string("/tmp/skills/review"),
                            "scope": .string("user"),
                        ]),
                        .object([
                            "description": .string("別のレビュー"),
                            "enabled": .bool(true),
                            "name": .string("review"),
                            "path": .string("/tmp/skills/review-repo"),
                            "scope": .string("repo"),
                        ]),
                        .object([
                            "description": .string("無効"),
                            "enabled": .bool(false),
                            "name": .string("disabled"),
                            "path": .string("/tmp/skills/disabled"),
                            "scope": .string("user"),
                        ]),
                    ]),
                ])])])
            case "thread/list":
                result = .object(["data": .array([.object([
                    "id": .string("codex-child-1"),
                    "parentThreadId": .string("codex-integration-thread"),
                    "preview": .string("stale child summary"),
                    "status": .object([
                        "type": .string("active"),
                        "activeFlags": .array([]),
                    ]),
                    "turns": .array([.object([
                        "id": .string("codex-child-turn-1-stale"),
                        "status": .string("inProgress"),
                        "items": .array([]),
                    ])]),
                ]), .object([
                    "id": .string("codex-child-2"),
                    "parentThreadId": .string("codex-integration-thread"),
                    "preview": .string("second child summary"),
                    "status": .object([
                        "type": .string("active"),
                        "activeFlags": .array([]),
                    ]),
                    "turns": .array([.object([
                        "id": .string("codex-child-2-turn-1"),
                        "status": .string("inProgress"),
                        "items": .array([]),
                    ])]),
                ]), .object([
                    "id": .string("codex-child-1"),
                    "parentThreadId": .string("codex-integration-thread"),
                    "preview": .string("latest child summary"),
                    "status": .object([
                        "type": .string("idle"),
                        "activeFlags": .array([]),
                    ]),
                    "turns": .array([.object([
                        "id": .string("codex-child-turn-1-latest"),
                        "status": .string("completed"),
                        "items": .array([.object([
                            "type": .string("agentMessage"),
                            "text": .string("latest child content"),
                        ])]),
                    ])]),
                ])])])
            case "thread/read":
                result = .object(["thread": .object([
                    "id": .string("codex-child-1"),
                    "parentThreadId": .string("codex-integration-thread"),
                    "status": .object([
                        "type": .string("active"),
                        "activeFlags": .array([]),
                    ]),
                    "turns": .array([.object([
                        "id": .string("codex-child-turn-1"),
                        "status": .string("inProgress"),
                        "items": .array([
                            .object([
                                "id": .string("child-item-1"),
                                "type": .string("userMessage"),
                                "text": .string("child question"),
                            ]),
                            .object([
                                "id": .string("child-item-2"),
                                "type": .string("agentMessage"),
                                "text": .string("child answer"),
                            ]),
                        ]),
                    ])]),
                ])])
            case "turn/interrupt":
                result = .object([:])
            case "permissionProfile/list", "collaborationMode/list":
                result = .object(["data": .array([])])
            default:
                result = .object([:])
            }

            let response: JSONValue = .object([
                "jsonrpc": .string("2.0"),
                "id": .number(Double(id)),
                "result": result,
            ])
            continuation.yield(try JSONEncoder().encode(response))
        }

        func close() async {
            continuation.finish()
        }

        func receive(_ line: String) {
            continuation.yield(Data(line.utf8))
        }

        func messages() async -> [JSONValue] { await recorder.snapshot }
    }

    private func makeCodexVM(
        client: any StructuredAgentClient = RecordingClient(),
        historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])? = nil,
        historyLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])? = nil
    ) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-codex-parity",
            historyProvider: historyProvider,
            historyTranscriptLoader: historyLoader
        )
    }

    private enum ObservationWaitError: Error {
        case timedOut
    }

    private func awaitObservation(
        timeout: Duration = .seconds(2),
        observing: @escaping () -> Void,
        trigger: () -> Void
    ) async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            observing()
        } onChange: {
            continuation.yield()
            continuation.finish()
        }
        trigger()
        defer { continuation.finish() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                guard await iterator.next() != nil else {
                    throw ObservationWaitError.timedOut
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ObservationWaitError.timedOut
            }
            defer { group.cancelAll() }
            guard try await group.next() != nil else {
                throw ObservationWaitError.timedOut
            }
        }
    }

    private func withTerminatedViewModel<T>(
        _ viewModel: ChatSessionViewModel,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            let result = try await operation()
            await viewModel.terminate()
            return result
        } catch {
            await viewModel.terminate()
            throw error
        }
    }

    private func historyEntry(id: String = "codex-history-1") -> ClaudeSessionHistoryEntry {
        ClaudeSessionHistoryEntry(
            sessionID: id,
            preview: "履歴から再開する Codex thread",
            firstUserAt: Date(timeIntervalSince1970: 10),
            lastModified: Date(timeIntervalSince1970: 20),
            gitBranch: "main",
            fileURL: URL(fileURLWithPath: "/tmp/\(id).jsonl")
        )
    }

    private func taskCards(in viewModel: ChatSessionViewModel) -> [([AgentTaskItem])] {
        viewModel.transcript.compactMap { item in
            guard case .taskList(_, let tasks, _) = item else { return nil }
            return tasks
        }
    }

    @Test("Codex 履歴は既存の一覧・詳細・再開 surface へ届く")
    func codexHistoryUsesExistingSurfaceAndSelectedResumeID() async throws {
        let client = RecordingClient()
        let entry = historyEntry()
        let viewModel = makeCodexVM(
            client: client,
            historyProvider: { [entry] },
            historyLoader: { _ in
                [
                    .userMessage(id: "history-user", text: "過去の質問", timestamp: Date()),
                    .agentMessage(id: "history-agent", text: "過去の回答", timestamp: Date()),
                ]
            }
        )

        try await withTerminatedViewModel(viewModel) {
            // startNew は履歴キャッシュのロード完了を待つため、polling を使わず
            // 起動経路自身の完了をバリアとして利用する。
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            #expect(viewModel.historyEntries == [entry], "Codex 履歴一覧が現在の session cwd の結果を保持すること")
            #expect(viewModel.shouldOfferHistoryStart, "Codex の新規チャットでも履歴から再開を提示すること")

            await viewModel.startFromHistory(entry)
            #expect(await client.resumes == [entry.sessionID], "選択した履歴 ID だけを resume へ渡すこと")
            #expect(viewModel.threadId == entry.sessionID, "resume 成功後の current thread ID が選択 ID と一致すること")
            #expect(viewModel.transcript.contains { $0.id == "history-agent" })
        }
    }

    @Test("Codex の plan/background/sub-agent 通知は別 surface を混線させない")
    func codexEventsReachTranscriptAndSeparateSurfaces() async throws {
        let client = RecordingClient()
        let viewModel = makeCodexVM(client: client)

        try await withTerminatedViewModel(viewModel) {
            try await awaitObservation(
                observing: { _ = viewModel.completedTurnSeq },
                trigger: {
                    client.yield(.turnStarted)
                    client.yield(.taskListUpdated(tasks: [
                        AgentTaskItem(id: "plan-1", title: "履歴を接続", status: .inProgress),
                        AgentTaskItem(id: "plan-2", title: "UIを更新", status: .pending),
                    ]))
                    client.yield(.backgroundTaskStarted(
                        taskId: "process-1",
                        taskType: "backgroundTerminal",
                        description: "npm test",
                        toolUseId: "item-1"
                    ))
                    client.yield(.subAgentStarted(
                        toolUseId: "child-thread-1",
                        subagentType: "explorer",
                        description: "Codex child thread"
                    ))
                    client.yield(.subAgentOutput(toolUseId: "child-thread-1", text: "child-only-output"))
                    client.yield(.turnCompleted(nativeSessionId: "codex-thread-1"))
                }
            )

            #expect(taskCards(in: viewModel).count == 1)
            #expect(taskCards(in: viewModel).first?.map(\.id) == ["plan-1", "plan-2"])
            #expect(viewModel.runningBackgroundTasks.contains { $0.taskId == "process-1" },
                    "Codex background terminal が親 turn 完了で消えず、一覧 surface に残ること")
            #expect(!viewModel.transcript.contains { $0.plainText.contains("child-only-output") },
                    "child output を親 transcript へ混ぜないこと")
            #expect(viewModel.subAgentTranscript(for: "child-thread-1").contains {
                $0.plainText.contains("child-only-output")
            })
        }
    }

    @Test("Codex 画像入力は app-server wire で画像を捨てない")
    func codexImageInputRemainsNativeAcrossViewModelAndClient() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = makeCodexVM(client: adapter)
        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            #expect(viewModel.availableModels.map(\.id) == ["gpt-5-codex"])
            let attachment = Data([0x89, 0x50, 0x4E, 0x47])
            #expect(viewModel.attachmentStore.addImage(
                data: attachment,
                mediaType: "image/png",
                filename: "evidence.png"
            ) != nil)

            try await viewModel.sendText("画像を確認", submit: true)

            let messages = await transport.messages()
            let request = try #require(messages.first { message in
                message["method"]?.stringValue == "turn/start"
            })
            let input = try #require(request["params"]?["input"])
            guard case .array(let values) = input else {
                Issue.record("turn/start input が配列でない")
                return
            }
            #expect(values.count == 2, "text と native image の2要素を wire へ送ること")
            #expect(values.contains { value in
                value["type"]?.stringValue == "localImage"
                    || value["type"]?.stringValue == "image"
            }, "画像要素を text-only へ丸めないこと")
        }
    }

    @Test("Codex 子 thread の詳細読込と停止は実 app-server RPC を通る")
    func codexSubAgentDetailAndStopUseNativeRPC() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = makeCodexVM(client: adapter)
        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            await viewModel.refreshCodexSubAgents()
            #expect(viewModel.codexSubAgentState?.children.map(\.id) == [
                "codex-child-1",
                "codex-child-2",
            ])
            let children = try #require(viewModel.codexSubAgentState?.children)
            #expect(children.map(\.id) == ["codex-child-1", "codex-child-2"],
                    "重複 child は初回の配列位置を維持すること")
            #expect(children.map(\.summary) == ["latest child summary", "second child summary"],
                    "同一 ID の child は最新 content を採用すること")
            #expect(children.first?.status == "idle",
                    "同一 ID の child は最新 status を採用すること")
            #expect(children.first?.activeTurnId == nil,
                    "同一 ID の child は最新 turn を採用すること")
            #expect(children.last?.activeTurnId == "codex-child-2-turn-1")
            await viewModel.loadCodexSubAgentDetail(threadID: "codex-child-1")

            let state = try #require(viewModel.codexSubAgentState)
            #expect(state.detail(for: "codex-child-1")?.transcript == ["child question", "child answer"])
            #expect(state.transcript(for: "codex-child-1") == ["child question", "child answer"])

            await viewModel.stopCodexSubAgent(threadID: "codex-child-2")
            let interrupt = try #require((await transport.messages()).last { message in
                message["method"]?.stringValue == "turn/interrupt"
            })
            #expect(interrupt["params"]?["threadId"] == .string("codex-child-2"))
            #expect(interrupt["params"]?["turnId"] == .string("codex-child-2-turn-1"))
            #expect(viewModel.codexSubAgentState?.stopState(for: "codex-child-2") == .stopping)

            try await awaitObservation(
                observing: { _ = viewModel.codexSubAgentState?.stopState(for: "codex-child-2") },
                trigger: {
                    transport.receive(#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"codex-child-2","turn":{"id":"codex-child-2-turn-1","status":"interrupted","items":[]}}}"#)
                }
            )
            #expect(viewModel.codexSubAgentState?.stopState(for: "codex-child-2") == .stopped)
            #expect(viewModel.codexSubAgentState?.children.last?.status == "interrupted")
            #expect(viewModel.codexSubAgentState?.children.last?.activeTurnId == nil)
        }
    }

    @Test("ChatComposer は Codex skill の name/path identity を slash 候補へ反映する")
    func chatComposerUpdatesCodexSkillSuggestionsThroughViewModel() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = makeCodexVM(client: adapter)
        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            await viewModel.codexSkillSelectionState?.refresh()

            let composer = ChatComposer(
                viewModel: viewModel,
                text: .constant("/rev"),
                isRunning: false,
                canSend: true,
                onSend: {},
                onInterrupt: {}
            )
            composer.suggestionControllerForTesting.update(text: "/rev", cursorUTF16: 4)
            composer.updateCodexSkillSuggestions()

            #expect(composer.suggestionControllerForTesting.candidates.map(\.skillIdentity?.path) == [
                "/tmp/skills/review",
                "/tmp/skills/review-repo",
            ])
            #expect(composer.suggestionControllerForTesting.candidates.allSatisfy {
                $0.skillIdentity?.name == "review"
            })
        }
    }

    @Test("Codex の skill と本文と画像は sendText から同じ native turn/start に届く")
    func codexSendTextUsesNativeSkillIdentityWithTextAndImage() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = makeCodexVM(client: adapter)
        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            let skillState = try #require(viewModel.codexSkillSelectionState)
            await skillState.refresh()
            #expect(skillState.select(name: "review", path: "/tmp/skills/review"))
            #expect(viewModel.attachmentStore.addImage(
                data: Data([0x89, 0x50, 0x4E, 0x47]),
                mediaType: "image/png",
                filename: "evidence.png"
            ) != nil)

            try await viewModel.sendText("本文", submit: true)

            let messages = await transport.messages()
            let request = try #require(messages.last { message in
                message["method"]?.stringValue == "turn/start"
            })
            let rawInput = try #require(request["params"]?["input"])
            guard case .array(let values) = rawInput else {
                Issue.record("native turn/start input が配列でない")
                return
            }
            #expect(values.count == 3)
            let hasText = values.contains { value in
                value["type"]?.stringValue == "text" && value["text"]?.stringValue == "本文"
            }
            let hasSkill = values.contains { value in
                value["type"]?.stringValue == "skill"
                    && value["name"]?.stringValue == "review"
                    && value["path"]?.stringValue == "/tmp/skills/review"
            }
            let hasImage = values.contains { value in value["type"]?.stringValue == "localImage" }
            #expect(hasText)
            #expect(hasSkill)
            #expect(hasImage)
        }
    }

    @Test("子 thread の interrupted completion は stop state だけを更新し、親 turn を終了しない")
    func childInterruptedCompletionDoesNotEndParentTurn() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        let viewModel = makeCodexVM(client: adapter)
        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            await viewModel.refreshCodexSubAgents()
            await viewModel.stopCodexSubAgent(threadID: "codex-child-2")
            #expect(viewModel.codexSubAgentState?.stopState(for: "codex-child-2") == .stopping)

            transport.receive(#"{"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"codex-integration-thread","turn":{"id":"parent-turn","status":"inProgress","items":[]}}}"#)
            try await awaitObservation(
                observing: { _ = viewModel.status },
                trigger: {}
            )
            #expect(viewModel.status == .running)

            try await awaitObservation(
                observing: { _ = viewModel.codexSubAgentState?.stopState(for: "codex-child-2") },
                trigger: {
                    transport.receive(#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"codex-child-2","turn":{"id":"codex-child-2-turn-1","status":"interrupted","items":[]}}}"#)
                }
            )
            #expect(viewModel.codexSubAgentState?.stopState(for: "codex-child-2") == .stopped)
            #expect(viewModel.status == .running)
            #expect(viewModel.completedTurnSeq == 0)
        }
    }
}
