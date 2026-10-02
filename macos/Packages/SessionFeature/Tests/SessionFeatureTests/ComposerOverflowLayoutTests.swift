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
    func denseOneRowKeepsRequiredControlsAndHidesOnlyPermissionAndBranch() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let footer = makeFooter(vm, layout: .standard)
        let width = try intrinsicWidth(footer) - 20
        let size = try renderSize(footer, proposedWidth: width)
        #expect(size.width <= width + epsilon)
        #expect(size.height == 26)
        let snapshot = accessibilitySnapshot(footer, width: width, height: size.height)
        expectDenseControls(snapshot)
    }

    @Test @MainActor
    func narrowOneRowKeepsContextAndSendButton() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let footer = makeFooter(vm, layout: .compact)
        let size = try renderSize(footer, proposedWidth: worstCaseWidth)
        #expect(size.width <= worstCaseWidth + epsilon)
        #expect(size.height == 26)
        let snapshot = accessibilitySnapshot(footer, width: worstCaseWidth, height: size.height)
        expectNarrowControls(snapshot)
        let overflow = try #require(snapshot.frames["ChatComposer.overflowMenu"])
        let send = try #require(snapshot.frames["ChatComposer.sendButton"])
        #expect(abs(overflow.midY - send.midY) <= epsilon)
    }

    @Test @MainActor
    func minimalLayoutKeepsRequiredControls() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let footer = makeFooter(vm, layout: .minimal)
        let size = try renderSize(footer, proposedWidth: worstCaseWidth)
        #expect(size.width <= worstCaseWidth + epsilon)
        #expect(size.height == 26)
        expectNarrowControls(accessibilitySnapshot(footer, width: worstCaseWidth, height: size.height))
    }

    @MainActor
    private func makeFooter(_ vm: ChatSessionViewModel, layout: ComposerFooterLayout) -> ChatComposerFooter {
        ChatComposerFooter(
            viewModel: vm, layout: layout, isRunning: false, canSubmit: true,
            onSend: {}, onInterrupt: {}, branchNameOverride: "feature/composer-overflow"
        )
    }

    @MainActor
    private func expectDenseControls(_ snapshot: FooterAccessibilitySnapshot, actionIdentifier: String = "sendButton") {
        for identifier in ["attachPlaceholder", "spawnModelMenu", "claudeEffortMenu", "overflowMenu", "contextIndicator", actionIdentifier] {
            #expect(snapshot.frames["ChatComposer.\(identifier)"] != nil, "Missing \(identifier)")
        }
        #expect(snapshot.frames["ChatComposer.claudePermissionMenu"] == nil)
        #expect(!snapshot.text.contains("feature/composer-overflow"))
        #expect(snapshot.text.contains("25%"))
        #expect(snapshot.text.contains("コンテキスト 25%"))
    }

    @MainActor
    private func expectNarrowControls(_ snapshot: FooterAccessibilitySnapshot, actionIdentifier: String = "sendButton") {
        for identifier in ["attachPlaceholder", "overflowMenu", "contextIndicator", actionIdentifier] {
            #expect(snapshot.frames["ChatComposer.\(identifier)"] != nil, "Missing \(identifier)")
        }
        for identifier in ["spawnModelMenu", "claudeEffortMenu", "claudePermissionMenu"] {
            #expect(snapshot.frames["ChatComposer.\(identifier)"] == nil, "Unexpected \(identifier)")
        }
        #expect(!snapshot.text.contains("feature/composer-overflow"))
        #expect(snapshot.text.contains("25%"))
        #expect(snapshot.text.contains("コンテキスト 25%"))
    }

    @MainActor
    private func accessibilitySnapshot<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> FooterAccessibilitySnapshot {
        let hosting = NSHostingView(rootView: content.environment(\.locale, Locale(identifier: "ja_JP")))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        defer { window.close() }
        var snapshot = FooterAccessibilitySnapshot()
        var seen = Set<ObjectIdentifier>()
        func visit(_ element: Any) {
            let object = element as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let identifier = object.accessibilityIdentifier() {
                snapshot.frames[identifier] = object.accessibilityFrame()
            }
            for value in [object.accessibilityLabel(), object.accessibilityValue()] {
                if let text = value { snapshot.text.insert(text) }
            }
            if let children = object.accessibilityChildren() { children.forEach(visit) }
            if let view = element as? NSView { view.subviews.forEach(visit) }
        }
        visit(hosting)
        return snapshot
    }

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
    func minimalComposerFooterKeepsControlsWithinReproductionWidth() async throws {
        try await expectMinimalFooterFits(width: reproductionWidth)
    }

    @Test @MainActor
    func minimalComposerFooterKeepsControlsWithinWorstCaseWidth() async throws {
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
    func measuredFooterIntrinsicWidthsKeepFullControlsInMinimalLayout() async throws {
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
        #expect(abs(minimalWidth - compactWidth) <= epsilon)
        let controlsWidth = try intrinsicWidth(ComposerSettingsControlsView(viewModel: vm, layout: .compact, side: .leading))
        #expect(minimalWidth > controlsWidth)
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
        try writeComposerPNG(
            viewModel: minimalVM,
            width: worstCaseWidth,
            url: URL(fileURLWithPath: "/tmp/composer-narrowest.png")
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

    /// 詰めた 1 段にも入らない幅では、モデル・effort を隠し、コンテキストと中断を 1 段に残す。
    @Test @MainActor
    func narrowFooterKeepsContextAndStopButtonInOneRow() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let footer = ChatComposerFooter(
            viewModel: vm,
            layout: .compact,
            isRunning: true,
            canSubmit: true,
            onSend: {},
            onInterrupt: {}
        )
        let size = try renderSize(footer, proposedWidth: worstCaseWidth)

        #expect(size.width <= worstCaseWidth + epsilon)
        #expect(size.height == 26)
        expectNarrowControls(accessibilitySnapshot(footer, width: worstCaseWidth, height: size.height), actionIdentifier: "stopButton")
    }

    /// 権限とブランチを「…」へ移すと入る幅なら、% の数字を残して 1 段に収める。
    @Test @MainActor
    func denseFooterKeepsChipsInOneRow() async throws {
        let vm = try await makeWorstCaseClaudeViewModel()
        let footer = ChatComposerFooter(
            viewModel: vm,
            layout: .compact,
            isRunning: true,
            canSubmit: true,
            onSend: {},
            onInterrupt: {}
        )
        let oneRowWidth = try intrinsicWidth(footer)
        let size = try renderSize(footer, proposedWidth: oneRowWidth - 20)

        #expect(size.width <= oneRowWidth - 20 + epsilon)
        #expect(size.height == 26)
        expectDenseControls(accessibilitySnapshot(footer, width: oneRowWidth - 20, height: size.height), actionIdentifier: "stopButton")
    }

    /// モデル名や effort のチップは、狭い幅を渡されても省略せず全文の幅で描く。
    @Test @MainActor
    func chipLabelKeepsTheFullTitle() throws {
        let label = ComposerChipLabel(title: "Opus 4.7 (1M context)")
        let fullWidth = try intrinsicWidth(label)
        let squeezed = try renderSize(label, proposedWidth: 60)
        #expect(fullWidth > 60)
        #expect(abs(squeezed.width - fullWidth) <= epsilon)
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

        let footer = ChatComposerFooter(
            viewModel: vm,
            layout: layout,
            isRunning: true,
            canSubmit: true,
            onSend: {},
            onInterrupt: {},
            branchNameOverride: "feature/composer-overflow",
            branchIsCheckingOutOverride: true
        )
        let renderedSize = try renderSize(footer, proposedWidth: width)

        #expect(renderedSize.width <= width + epsilon)
        #expect(renderedSize.height == 26)
        let snapshot = accessibilitySnapshot(footer, width: width, height: renderedSize.height)
        if width == worstCaseWidth {
            expectNarrowControls(snapshot, actionIdentifier: "stopButton")
        } else {
            expectDenseControls(snapshot, actionIdentifier: "stopButton")
        }
    }

    @MainActor
    private func writeComposerPNG(
        viewModel: ChatSessionViewModel,
        width: CGFloat,
        url: URL
    ) throws {
        let layout = ComposerLayout.controlsLayout(proposedWidth: width)
        // 「…」は AppKit の Menu なので、ImageRenderer ではなく実際の NSHostingView を撮る。
        let hosting = NSHostingView(
            rootView: ChatComposer(
                viewModel: viewModel,
                text: .constant("Hello"),
                isRunning: true,
                canSend: true,
                controlsLayout: layout,
                onSend: {},
                onInterrupt: {}
            )
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
        )
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        defer { window.close() }
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
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

private struct FooterAccessibilitySnapshot {
    var frames: [String: CGRect] = [:]
    var text: Set<String> = []
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
