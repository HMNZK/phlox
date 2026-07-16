// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — グリッドタイルの composer が狭いタイル幅からはみ出さない。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面（未実装の間はコンパイル赤＝red 状態）:
// - ComposerLayout.gridControlsLayout(proposedWidth:) -> ComposerFooterLayout
//   （グリッドは standard を持たない: 広い→.compact / minimalControlsWidthThreshold 未満→.minimal）
// - GridComposerBar を internal にし、ImageRenderer で直接描画可能にする

import AppKit
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Grid composer overflow acceptance (task-1)", .serialized)
struct AcceptanceGridComposerOverflowTests {
    private let epsilon: CGFloat = 1

    @Test @MainActor
    func グリッドのレイアウト方針は広くてもcompact_しきい値未満はminimal() {
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: 1000) == .compact)
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold) == .compact)
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold - 1) == .minimal)
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: 290) == .minimal)
    }

    @Test(arguments: [CGFloat(290), CGFloat(250)]) @MainActor
    func 狭いタイル幅でグリッドcomposerが提案幅に収まる(width: CGFloat) async throws {
        let vm = try await makeClaudeViewModel()
        let size = try renderSize(
            GridComposerBar(
                viewModel: vm,
                text: .constant("hello"),
                onSend: {},
                onInterrupt: {}
            ),
            proposedWidth: width
        )
        #expect(size.width <= width + epsilon)
    }

    @Test @MainActor
    func 広いタイル幅でもグリッドcomposerが提案幅に収まる() async throws {
        let vm = try await makeClaudeViewModel()
        let size = try renderSize(
            GridComposerBar(
                viewModel: vm,
                text: .constant("hello"),
                onSend: {},
                onInterrupt: {}
            ),
            proposedWidth: 700
        )
        #expect(size.width <= 700 + epsilon)
    }

    // MARK: - Harness

    @MainActor
    private func makeClaudeViewModel() async throws -> ChatSessionViewModel {
        let client = GridAcceptanceStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-grid-composer-fixture",
            spawnAgentModelsProvider: { ["opus", "sonnet", "haiku"] }
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        await vm.setSpawnAgentModel("opus")
        await vm.setSpawnAgentEffort("max")
        await vm.setSpawnAgentPermission("bypassPermissions")
        client.yield(.turnUsage(TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)))
        try await vm.sendText("rendering", submit: true)
        try await waitUntil { vm.lastTurnUsage != nil && vm.status.isRunning }
        return vm
    }

    @MainActor
    private func renderSize<Content: View>(_ content: Content, proposedWidth: CGFloat) throws -> CGSize {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: proposedWidth, height: nil)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        return image.size
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        _ condition: @escaping () -> Bool
    ) async throws {
        var elapsed: UInt64 = 0
        while !condition() {
            guard elapsed < timeoutNanoseconds else {
                Issue.record("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            elapsed += pollIntervalNanoseconds
        }
    }
}

private final class GridAcceptanceStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}
