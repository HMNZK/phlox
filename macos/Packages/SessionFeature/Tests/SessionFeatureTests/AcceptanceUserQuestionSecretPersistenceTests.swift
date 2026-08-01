// 契約の正本: tasks/task-6.md — 伏せ字（isSecret）の回答を永続化・エクスポートに平文で残さない。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。

import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private let secretAnswer = "sk-live-SUPER-SECRET-0123456789"
private let shortSecret = "pw1"

private final class SilentClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

/// ハンドラが返した wire レスポンスを 1 回だけ記録する箱
/// （`Task.value` の await はキャンセル不能なので使わない）。
private actor ResponseBox {
    private var value: JSONValue?
    func set(_ response: JSONValue?) { if value == nil { value = response } }
    var current: JSONValue? { value }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @escaping () -> Bool
) async -> Bool {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
        elapsed += 10_000_000
    }
    return true
}

private func awaitResponse(_ box: ResponseBox, timeout: UInt64 = 2_000_000_000) async -> JSONValue? {
    var elapsed: UInt64 = 0
    while elapsed < timeout {
        if let value = await box.current { return value }
        try? await Task.sleep(nanoseconds: 20_000_000)
        elapsed += 20_000_000
    }
    return await box.current
}

private func codexRequest(isSecret: Bool) -> ToolRequestUserInputRequest {
    ToolRequestUserInputRequest(
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: [
            ToolRequestUserInputQuestion(
                id: "q-secret",
                header: "認証",
                question: "API キーを入力してください",
                options: nil,
                isOther: true,
                isSecret: isSecret
            )
        ]
    )
}

@MainActor
private func firstQuestionRequestId(_ vm: ChatSessionViewModel) -> String? {
    for item in vm.transcript {
        if case .userQuestion(_, let requestId, _, _, _, _) = item { return requestId }
    }
    return nil
}

@MainActor
private func firstQuestionItem(_ vm: ChatSessionViewModel) -> ChatItem? {
    vm.transcript.first {
        if case .userQuestion = $0 { return true }
        return false
    }
}

@MainActor
private func storedAnswers(_ vm: ChatSessionViewModel) -> [String: [String]]? {
    guard case .userQuestion(_, _, _, let answers, _, _) = firstQuestionItem(vm) else { return nil }
    return answers
}

/// 質問を1件出し、`answer` で回答するところまで進めて、VM と wire レスポンスを返す。
@MainActor
private func answerOneQuestion(
    isSecret: Bool,
    answer: String
) async throws -> (vm: ChatSessionViewModel, response: JSONValue?) {
    let client = SilentClient()
    let broker = ChatApprovalBroker()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-codex-secret-persistence-test"
    )

    client.yield(.turnStarted)
    _ = await waitUntil { vm.status == .running }

    let handler = broker.serverRequestHandler
    let box = ResponseBox()
    Task {
        let response = try? await handler(.userInputRequest(codexRequest(isSecret: isSecret)))
        await box.set(response)
    }

    let appeared = await waitUntil { firstQuestionRequestId(vm) != nil }
    #expect(appeared, "質問カードが表示されない")
    let requestId = try #require(firstQuestionRequestId(vm))

    _ = await vm.respondToUserQuestion(requestId: requestId, answers: ["q-secret": [answer]])
    let response = await awaitResponse(box)
    return (vm, response)
}

/// wire レスポンス `{"answers": {"<qid>": {"answers": [...]}}}` から回答配列を取り出す。
private func wireAnswers(_ response: JSONValue?, questionId: String) -> [String]? {
    guard case .object(let root)? = response,
          case .object(let byQuestion)? = root["answers"],
          case .object(let entry)? = byQuestion[questionId],
          case .array(let values)? = entry["answers"]
    else { return nil }
    return values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
}

private func exportMetadata() -> ChatTranscriptExportMetadata {
    ChatTranscriptExportMetadata(
        sessionTitle: "Lotus",
        agentName: "Codex",
        projectName: "Phlox",
        workingDirectory: "/tmp/phlox",
        exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

@Suite("Acceptance: 伏せ字の回答を永続化・エクスポートに残さない（task-6）")
struct AcceptanceUserQuestionSecretPersistenceTests {
    @Test @MainActor
    func 実際の回答はwireへ届く() async throws {
        // 破棄は「送信のあと」。順序を逆にすると Codex へマスク文字列が届いて機能が壊れる。
        let (_, response) = try await answerOneQuestion(isSecret: true, answer: secretAnswer)
        let sent = try #require(wireAnswers(response, questionId: "q-secret"))
        #expect(sent == [secretAnswer], "wire には素の回答を送ること（マスク後の値を送らない）")
    }

    @Test @MainActor
    func 伏せ字の回答は転写に平文で残らない() async throws {
        let (vm, _) = try await answerOneQuestion(isSecret: true, answer: secretAnswer)
        let answers = try #require(storedAnswers(vm), "回答済みカードに answers が積まれていない")
        let flattened = answers.values.flatMap { $0 }
        #expect(!flattened.contains(secretAnswer), "伏せ字の回答が転写に平文で残っている")
        #expect(!flattened.isEmpty, "回答済みであることは残すこと（answers を空にして誤魔化さない）")
    }

    @Test @MainActor
    func 伏せ字の回答は永続化JSONに現れない() async throws {
        let (vm, _) = try await answerOneQuestion(isSecret: true, answer: secretAnswer)
        let item = try #require(firstQuestionItem(vm))
        let data = try JSONEncoder().encode([item])
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains(secretAnswer), "永続化 JSON に平文の回答が書き出されている")
    }

    @Test @MainActor
    func 伏せ字の回答はエクスポートに現れない() async throws {
        let (vm, _) = try await answerOneQuestion(isSecret: true, answer: secretAnswer)
        let markdown = ChatTranscriptExporter.markdown(items: vm.transcript, metadata: exportMetadata())
        #expect(!markdown.contains(secretAnswer), "エクスポート Markdown に平文の回答が書き出されている")
    }

    @Test @MainActor
    func マスクは回答の長さを漏らさない() async throws {
        let (longVM, _) = try await answerOneQuestion(isSecret: true, answer: secretAnswer)
        let (shortVM, _) = try await answerOneQuestion(isSecret: true, answer: shortSecret)
        let long = try #require(storedAnswers(longVM)?.values.flatMap { $0 })
        let short = try #require(storedAnswers(shortVM)?.values.flatMap { $0 })
        #expect(long == short, "マスクが回答の長さに依存している（長さが漏れる）")
    }

    @Test @MainActor
    func 伏せ字でない質問の回答はそのまま残る() async throws {
        let plain = "A案"
        let (vm, response) = try await answerOneQuestion(isSecret: false, answer: plain)
        #expect(wireAnswers(response, questionId: "q-secret") == [plain])
        let answers = try #require(storedAnswers(vm))
        #expect(answers.values.flatMap { $0 } == [plain], "isSecret でない回答まで消してはいけない")

        let markdown = ChatTranscriptExporter.markdown(items: vm.transcript, metadata: exportMetadata())
        #expect(markdown.contains(plain), "isSecret でない回答はエクスポートに出ること")
    }

    @Test
    func エクスポートはidをキーにした回答を引き当てる() throws {
        // Codex の質問は `id` が回答キー（answerKey）。`question` 文字列で引くと回答が出ない。
        let item = ChatItem.userQuestion(
            id: "question-1",
            requestId: "req-1",
            questions: [
                ChatUserQuestion(
                    question: "どの方式にしますか？",
                    header: "方式",
                    options: [ChatUserQuestionOption(label: "A案")],
                    multiSelect: false,
                    id: "q-1"
                )
            ],
            answers: ["q-1": ["A案"]],
            state: .answered,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let markdown = ChatTranscriptExporter.markdown(items: [item], metadata: exportMetadata())
        #expect(markdown.contains("→ 回答: A案"), "id をキーにした回答がエクスポートに現れない")
    }
}
