import AppKit
import SwiftUI
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Composer overflow layout", .serialized)
struct ComposerOverflowLayoutTests {
    private let compactWidth: CGFloat = 500
    private let reproductionWidth: CGFloat = 360
    private let worstCaseWidth: CGFloat = 250
    private let wideWidth: CGFloat = 900
    private let epsilon: CGFloat = 1

    @Test @MainActor
    func controlsLayoutSwitchesAcrossStandardCompactAndMinimalThresholds() {
        #expect(ComposerLayout.controlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold - 1) == .minimal)
        #expect(ComposerLayout.controlsLayout(proposedWidth: ComposerLayout.minimalControlsWidthThreshold) == .compact)
        #expect(ComposerLayout.controlsLayout(proposedWidth: ComposerLayout.compactControlsWidthThreshold - 1) == .compact)
        #expect(ComposerLayout.controlsLayout(proposedWidth: ComposerLayout.compactControlsWidthThreshold) == .standard)
        #expect(ComposerLayout.controlsLayout(proposedWidth: wideWidth) == .standard)
    }

    @Test @MainActor
    func compactComposerFooterRendersWithinProposedWidth() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let layout = ComposerLayout.controlsLayout(proposedWidth: compactWidth)
        #expect(layout == .compact)

        let renderedSize = try renderSize(
            ChatComposerFooter(
                viewModel: vm,
                layout: layout,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            ),
            proposedWidth: compactWidth
        )

        #expect(renderedSize.width <= compactWidth + epsilon)
    }

    @Test @MainActor
    func minimalComposerFooterRendersWithinReproductionWidth() async throws {
        try await expectMinimalFooterFits(width: reproductionWidth)
    }

    @Test @MainActor
    func minimalComposerFooterRendersWithinWorstCaseWidth() async throws {
        try await expectMinimalFooterFits(width: worstCaseWidth)
    }

    @Test @MainActor
    func wideComposerFooterStaysStandardAndFitsProposedWidth() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let layout = ComposerLayout.controlsLayout(proposedWidth: wideWidth)
        #expect(layout == .standard)

        let renderedSize = try renderSize(
            ChatComposerFooter(
                viewModel: vm,
                layout: layout,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            ),
            proposedWidth: wideWidth
        )

        #expect(renderedSize.width <= wideWidth + epsilon)
    }

    @Test @MainActor
    func measuredFooterIntrinsicWidthsDocumentThresholdAndCompactFloor() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let standardWidth = try intrinsicWidth(
            ChatComposerFooter(
                viewModel: vm,
                layout: .standard,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            )
        )
        let compactWidth = try intrinsicWidth(
            ChatComposerFooter(
                viewModel: vm,
                layout: .compact,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            )
        )
        let minimalWidth = try intrinsicWidth(
            ChatComposerFooter(
                viewModel: vm,
                layout: .minimal,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            )
        )

        #expect(standardWidth.rounded(.up) <= ComposerLayout.compactControlsWidthThreshold - 40)
        #expect(compactWidth.rounded(.up) <= ComposerLayout.minimalControlsWidthThreshold - 10)
        #expect(minimalWidth < 200)
    }

    @Test @MainActor
    func writesComposerReferencePNGs() async throws {
        let narrowVM = try await makeWorstCaseClaudeViewModel()
        try writeComposerPNG(
            viewModel: narrowVM,
            width: compactWidth,
            url: URL(fileURLWithPath: "/tmp/composer-narrow.png")
        )

        let wideVM = try await makeWorstCaseClaudeViewModel()
        try writeComposerPNG(
            viewModel: wideVM,
            width: wideWidth,
            url: URL(fileURLWithPath: "/tmp/composer-wide.png")
        )

        let minimalVM = try await makeWorstCaseClaudeViewModel()
        try writeComposerPNG(
            viewModel: minimalVM,
            width: reproductionWidth,
            url: URL(fileURLWithPath: "/tmp/composer-minimal.png")
        )
    }

    @MainActor
    private func makeWorstCaseClaudeViewModel() async throws -> ChatSessionViewModel {
        let client = RenderingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-composer-overflow-fixture",
            spawnAgentModelsProvider: { ["opus", "sonnet", "fable", "haiku"] }
        )

        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        await vm.setSpawnAgentModel("opus")
        await vm.setSpawnAgentEffort("max")
        await vm.setSpawnAgentPermission("bypassPermissions")
        client.yield(.turnUsage(TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)))
        vm.draft = "Hello"
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
    private func intrinsicWidth<Content: View>(_ content: Content) throws -> CGFloat {
        let renderer = ImageRenderer(content: content.fixedSize(horizontal: true, vertical: false))
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        return image.size.width
    }

    @MainActor
    private func expectMinimalFooterFits(width: CGFloat) async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let layout = ComposerLayout.controlsLayout(proposedWidth: width)
        #expect(layout == .minimal)

        let renderedSize = try renderSize(
            ChatComposerFooter(
                viewModel: vm,
                layout: layout,
                isRunning: true,
                canSubmit: true,
                onSend: {},
                onInterrupt: {},
                branchNameOverride: "feature/composer-overflow",
                branchIsCheckingOutOverride: true
            ),
            proposedWidth: width
        )

        #expect(renderedSize.width <= width + epsilon)
    }

    @MainActor
    private func writeComposerPNG(
        viewModel: ChatSessionViewModel,
        width: CGFloat,
        url: URL
    ) throws {
        let layout = ComposerLayout.controlsLayout(proposedWidth: width)
        let renderer = ImageRenderer(
            content: ChatComposer(
                viewModel: viewModel,
                text: .constant("Hello"),
                isRunning: true,
                canSend: true,
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
        try png.write(to: url, options: .atomic)
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

private final class RenderingStructuredClient: StructuredAgentClient, @unchecked Sendable {
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
