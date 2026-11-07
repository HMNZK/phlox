import AppKit
import SwiftUI
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// 状態カードが実際の画面（ChatTranscriptView）につながっていること。
// Claude・Codex は実行中にカードの見出しが出て末尾の「考え中」の行は出ず、Cursor は今のまま（要件 D5・D6、AC-14）。

private final class HostedFakeClient: StructuredAgentClient, @unchecked Sendable {
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

@Suite("状態カード: 画面への接続（D5・D6・AC-14）", .serialized)
@MainActor
struct AgentStatusCardHostedTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var items: [ChatItem] {
        [
            .userMessage(id: "u1", text: "直して", timestamp: start, attachments: [], turnEnd: nil),
            .fileChange(
                id: "e1", changes: [FilePatchChange(path: "/repo/api.swift", diff: "@@\n-a\n+b", kind: "edit")],
                timestamp: start.addingTimeInterval(1), completedAt: nil
            ),
        ]
    }

    /// 実行中のセッションの会話を載せた画面を作り、AX の識別子を集める。
    private func identifiers(agent: AgentKind) async throws -> Set<String> {
        let client = HostedFakeClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(agent),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-agent-status-hosted-test"
        )
        client.yield(.turnStarted)
        let deadline = ContinuousClock.now + .seconds(2)
        while viewModel.status != .running {
            try #require(ContinuousClock.now < deadline, "実行中にならない")
            try await Task.sleep(for: .milliseconds(5))
        }

        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApplication.shared
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }

        let hosting = NSHostingView(rootView: ChatTranscriptView(viewModel: viewModel, transcript: items))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = hosting
        defer { window.close() }
        window.orderBack(nil)
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(30))
            hosting.layoutSubtreeIfNeeded()
        }
        let found = Self.collectIdentifiers(from: hosting)
        await viewModel.terminate()
        return found
    }

    private static func collectIdentifiers(from root: NSObject) -> Set<String> {
        var visited = Set<ObjectIdentifier>()
        var found = Set<String>()
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            let id = NSSelectorFromString("accessibilityIdentifier")
            if object.responds(to: id), let value = object.perform(id)?.takeUnretainedValue() as? String, !value.isEmpty {
                found.insert(value)
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                values.forEach(visit)
            }
            if let view = object as? NSView { view.subviews.forEach(visit) }
        }
        visit(root)
        return found
    }

    @Test("Claude の実行中は、カードの見出しが出て、考え中の行は出ない")
    func claudeShowsCardInsteadOfThinkingRow() async throws {
        let found = try await identifiers(agent: .claudeCode)

        #expect(found.contains("AgentStatusCard.header"))
        #expect(!found.contains("ChatThinkingIndicator"))
    }

    @Test("Codex の実行中も、カードの見出しが出て、考え中の行は出ない")
    func codexShowsCardInsteadOfThinkingRow() async throws {
        let found = try await identifiers(agent: .codex)

        #expect(found.contains("AgentStatusCard.header"))
        #expect(!found.contains("ChatThinkingIndicator"))
    }

    @Test("Cursor の実行中は、今のとおり考え中の行が出て、カードは出ない")
    func cursorKeepsTheThinkingRow() async throws {
        let found = try await identifiers(agent: .cursor)

        #expect(found.contains("ChatThinkingIndicator"))
        #expect(!found.contains("AgentStatusCard.header"))
        #expect(!found.contains("AgentStatusCard"))
    }
}
