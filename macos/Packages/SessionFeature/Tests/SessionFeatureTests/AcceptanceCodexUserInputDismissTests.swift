// 契約の正本: tasks/task-4.md（2026-08-01 に PM が再凍結した追加契約）。
// 独立レビューの MUST 指摘「declineUserQuestion に製品コードからの呼び出し元が無く、
// Codex の質問が terminate まで宙吊りになる」を塞ぐ受け入れテスト。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。

import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private final class DismissRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var interruptCount = 0

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws { interruptCount += 1 }
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

/// ハンドラの決着を1回だけ記録する箱（`Task.value` の await はキャンセル不能なので使わない）。
private actor WireBox {
    private var settled = false
    func mark() { settled = true }
    var isSettled: Bool { settled }
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

private func settled(_ box: WireBox, timeout: UInt64 = 2_000_000_000) async -> Bool {
    var elapsed: UInt64 = 0
    while elapsed < timeout {
        if await box.isSettled { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
        elapsed += 20_000_000
    }
    return await box.isSettled
}

private func codexRequest() -> ToolRequestUserInputRequest {
    ToolRequestUserInputRequest(
        threadId: "thread-1",
        turnId: "turn-1",
        itemId: "item-1",
        questions: [
            ToolRequestUserInputQuestion(
                id: "q1",
                header: "ヘッダ",
                question: "質問",
                options: [ToolRequestUserInputOption(label: "A案", description: "説明A")]
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

/// 製品コードのソースを読む（配線の存在を機械判定するため。同種の白箱検査が
/// UserQuestionFocusWhiteboxTests に既にある）。
private func source(of fileName: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SessionFeatureTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // SessionFeature(package root)
        .appendingPathComponent("Sources/SessionFeature/\(fileName)")
    return try String(contentsOf: url, encoding: .utf8)
}

@MainActor
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

@Suite("Acceptance: Codex 質問の拒否が wire を決着させる（task-4 追加契約）")
struct AcceptanceCodexUserInputDismissTests {
    @Test @MainActor
    func 拒否はwireを決着させてからターンを中断する() async throws {
        let client = DismissRecordingClient()
        let broker = ChatApprovalBroker()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: broker,
            workingDirectory: "/tmp/phlox-codex-dismiss-test"
        )
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let handler = broker.serverRequestHandler
            let box = WireBox()
            let requestTask = Task {
                _ = try? await handler(.userInputRequest(codexRequest()))
                await box.mark()
            }
            do {
                let appeared = await waitUntil { firstQuestionRequestId(vm) != nil }
                #expect(appeared)
                let requestId = try #require(firstQuestionRequestId(vm))

                let declined = await vm.declineUserQuestion(requestId: requestId)
                #expect(declined)

                // ここが本丸: 拒否したら Codex 側の要求が**決着している**こと（宙吊りにしない）。
                let wireSettled = await settled(box)
                #expect(wireSettled, "拒否は broker.declineUserInput で wire を決着させること（Codex を待たせない）")

                let interrupted = await waitUntil { client.interruptCount >= 1 }
                #expect(interrupted, "拒否はターンを中断すること（ゲート①の決定 D4）")
                _ = await requestTask.value
            } catch {
                await vm.terminate()
                requestTask.cancel()
                _ = await requestTask.value
                throw error
            }
        }
    }

    @Test @MainActor
    func ターン中断でも保留中の質問はwireを決着させる() async throws {
        // 2026-08-01 追記（独立レビュー2回目の HIGH 指摘）: 拒否ボタン以外の中断経路
        // （思考インジケータの中断ボタン・エラー経路・失効）でも、保留中の Codex 質問を
        // 決着させないと terminate まで宙吊りになる。入口ごとではなく**ターンが終わる時点で**塞ぐ。
        let client = DismissRecordingClient()
        let broker = ChatApprovalBroker()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: broker,
            workingDirectory: "/tmp/phlox-codex-interrupt-test"
        )
        try await withTerminatedViewModel(vm) {
            client.yield(.turnStarted)
            _ = await waitUntil { vm.status == .running }

            let handler = broker.serverRequestHandler
            let box = WireBox()
            let requestTask = Task {
                _ = try? await handler(.userInputRequest(codexRequest()))
                await box.mark()
            }
            _ = await waitUntil { firstQuestionRequestId(vm) != nil }

            // 拒否ボタンではなく、汎用のターン中断を呼ぶ。
            await vm.turnInterrupt()

            let wireSettled = await settled(box)
            #expect(wireSettled, "ターン中断でも保留中の質問を決着させること（Codex を宙吊りにしない）")
            _ = await requestTask.value
        }
    }

    @Test
    func 質問カードのdismissボタンが拒否経路へ配線されている() throws {
        // 到達性: `declineUserQuestion` を実装しても、カードの dismiss ボタンから呼ばれなければ
        // ユーザーには何も変わらない（独立レビューの MUST 指摘）。
        let transcript = try source(of: "ChatTranscriptView.swift")
        #expect(
            transcript.contains("declineUserQuestion"),
            "ChatTranscriptView の onDismissUserQuestion が declineUserQuestion を通っていない"
        )
    }
}
