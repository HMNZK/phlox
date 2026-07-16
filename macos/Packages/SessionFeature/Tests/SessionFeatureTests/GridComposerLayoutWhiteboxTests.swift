import AppKit
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Grid composer layout whitebox", .serialized)
struct GridComposerLayoutWhiteboxTests {
    private let epsilon: CGFloat = 1

    @Test @MainActor
    func gridControlsLayoutNeverReturnsStandard() {
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: 1000) == .compact)
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold) == .compact)
        #expect(ComposerLayout.gridControlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold - 1) == .minimal)
    }

    @Test @MainActor
    func writesGridComposerReferencePNGAt290() async throws {
        let vm = try await makeClaudeViewModel()
        let width: CGFloat = 290
        let layout = ComposerLayout.gridControlsLayout(proposedWidth: width)
        #expect(layout == .minimal)

        let renderer = ImageRenderer(
            content: GridComposerBar(
                viewModel: vm,
                text: .constant("hello"),
                controlsLayout: layout,
                onSend: {},
                onInterrupt: {}
            )
            .frame(width: width)
        )
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/grid-composer-290.png"), options: .atomic)

        let renderedSize = image.size
        #expect(renderedSize.width <= width + epsilon)
    }

    @MainActor
    private func makeClaudeViewModel() async throws -> ChatSessionViewModel {
        let client = GridWhiteboxStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-grid-composer-whitebox",
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

private final class GridWhiteboxStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured!
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
