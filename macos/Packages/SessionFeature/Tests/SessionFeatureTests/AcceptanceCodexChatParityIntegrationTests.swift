import Foundation
import Testing
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
            case "model/list", "permissionProfile/list", "collaborationMode/list":
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

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
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

        await waitUntil { viewModel.historyEntries == [entry] }
        #expect(viewModel.historyEntries == [entry], "Codex 履歴一覧が現在の session cwd の結果を保持すること")
        #expect(viewModel.shouldOfferHistoryStart, "Codex の新規チャットでも履歴から再開を提示すること")

        await viewModel.startFromHistory(entry)
        #expect(await client.resumes == [entry.sessionID], "選択した履歴 ID だけを resume へ渡すこと")
        #expect(viewModel.threadId == entry.sessionID, "resume 成功後の current thread ID が選択 ID と一致すること")
        #expect(viewModel.transcript.contains { $0.id == "history-agent" })
    }

    @Test("Codex の plan/background/sub-agent 通知は別 surface を混線させない")
    func codexEventsReachTranscriptAndSeparateSurfaces() async throws {
        let client = RecordingClient()
        let viewModel = makeCodexVM(client: client)

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

        await waitUntil {
            taskCards(in: viewModel).count == 1
                && viewModel.subAgents.contains { $0.id == "child-thread-1" }
        }

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

    @Test("Codex 画像入力は app-server wire で画像を捨てない")
    func codexImageInputRemainsNativeAcrossViewModelAndClient() async throws {
        let transport = JSONRPCTransport()
        let appServer = CodexAppServerClient(transport: transport)
        let adapter = CodexStructuredAgentClient(client: appServer)
        await adapter.start()
        _ = try await adapter.initialize(InitializeParams(
            clientInfo: ClientInfo(name: "phlox", title: "Phlox", version: "test"),
            capabilities: InitializeCapabilities(experimentalApi: true)
        ))
        _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/phlox-codex-parity"))

        let viewModel = makeCodexVM(client: adapter)
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

        await adapter.close()
    }
}
