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

/// 画面が出た後に、移動先を 1 度だけ渡す（実際のジャンプと同じく、値の変化で動く）。
private struct JumpHost: View {
    let viewModel: ChatSessionViewModel
    let items: [ChatItem]
    let jumpTo: String?
    @State private var target: String?

    var body: some View {
        ChatTranscriptView(viewModel: viewModel, transcript: items, requestedScrollTarget: $target)
            .task {
                try? await Task.sleep(for: .milliseconds(60))
                target = jumpTo
            }
    }
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
    /// `jumpTo`: 画面が出た後に移動先として渡す item の id（バックグラウンド作業の一覧からのジャンプ）。
    private func identifiers(
        agent: AgentKind, items: [ChatItem]? = nil, running: Bool = true, jumpTo: String? = nil
    ) async throws -> Set<String> {
        let client = HostedFakeClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(agent),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-agent-status-hosted-test"
        )
        if running {
            client.yield(.turnStarted)
            let deadline = ContinuousClock.now + .seconds(2)
            while viewModel.status != .running {
                try #require(ContinuousClock.now < deadline, "実行中にならない")
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApplication.shared
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }

        let hosting = NSHostingView(rootView: JumpHost(viewModel: viewModel, items: items ?? self.items, jumpTo: jumpTo))
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
            // 読み上げのラベルも集める（作業の行は識別子が行の要素として出ないため、ラベルで見る）。
            let label = NSSelectorFromString("accessibilityLabel")
            if object.responds(to: label), let value = object.perform(label)?.takeUnretainedValue() as? String, !value.isEmpty {
                found.insert("label:" + value)
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

    // MARK: - 作業への移動（バックグラウンド作業の一覧からのジャンプ）

    /// 終わったカード（タスク A は完了で閉じている。中に検索 c1 と編集 e1）を載せ、AX の識別子を集める。
    private func finishedCardIdentifiers(revealItemID: String?) async throws -> Set<String> {
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApplication.shared
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }

        func task(_ id: String, _ state: AgentTaskStatus) -> AgentTaskItem { AgentTaskItem(id: id, title: "タスク \(id)", status: state) }
        let ended = ChatTurnEnd(outcome: .completed, at: start.addingTimeInterval(30))
        let items: [ChatItem] = [
            .userMessage(id: "u1", text: "直して", timestamp: start, attachments: [], turnEnd: ended),
            .taskList(id: "tl1", tasks: [task("A", .inProgress)], timestamp: start.addingTimeInterval(1)),
            .commandExecution(
                id: "c1", command: "rg Retry-After", output: "出力", timestamp: start.addingTimeInterval(2),
                completedAt: start.addingTimeInterval(3), intent: nil
            ),
            .taskList(id: "tl2", tasks: [task("A", .completed)], timestamp: start.addingTimeInterval(9)),
        ]
        let card = try #require(AgentStatusCardBuilder.build(
            items: items,
            liveState: AgentStatusLiveState(isProcessing: false, activityState: .thinking, hangAssessment: nil, isAwaitingReply: false)
        ).compactMap { block -> AgentStatusCard? in if case .statusCard(let card) = block { card } else { nil } }.first)
        let request = revealItemID.map { AgentStatusRevealRequest(itemID: $0, serial: 1) }

        let hosting = NSHostingView(rootView: AgentStatusCardView(
            card: card, agentDescriptor: AgentRegistry.descriptor(for: .claudeCode), revealRequest: request
        ))
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
        return Self.collectIdentifiers(from: hosting)
    }

    @Test("作業への移動の要求があると、閉じたタスクの行が開いて中の作業の行が出る。要求が無ければ閉じたまま")
    func revealRequestOpensTheClosedTaskRow() async throws {
        let closed = try await finishedCardIdentifiers(revealItemID: nil)
        let opened = try await finishedCardIdentifiers(revealItemID: "c1")

        #expect(closed.contains("AgentStatusCard.row.task-A"))
        #expect(!closed.contains { $0.contains("rg Retry-After") })
        #expect(opened.contains { $0.contains("rg Retry-After") })
    }

    /// 終わった会話。タスク A（完了で閉じている）の中に検索 c1。
    private var finishedItems: [ChatItem] {
        func task(_ state: AgentTaskStatus) -> AgentTaskItem { AgentTaskItem(id: "A", title: "タスク A", status: state) }
        return [
            .userMessage(
                id: "u1", text: "直して", timestamp: start, attachments: [],
                turnEnd: ChatTurnEnd(outcome: .completed, at: start.addingTimeInterval(30))
            ),
            .taskList(id: "tl1", tasks: [task(.inProgress)], timestamp: start.addingTimeInterval(1)),
            .commandExecution(
                id: "c1", command: "rg Retry-After", output: "出力", timestamp: start.addingTimeInterval(2),
                completedAt: start.addingTimeInterval(3), intent: nil
            ),
            .taskList(id: "tl2", tasks: [task(.completed)], timestamp: start.addingTimeInterval(9)),
        ]
    }

    @Test("画面のジャンプ: 閉じたタスクの中の作業へ移動すると、そのタスクの行が開く。移動しなければ閉じたまま")
    func jumpOpensTheClosedTaskRowInTheTranscript() async throws {
        let stay = try await identifiers(agent: .claudeCode, items: finishedItems, running: false)
        let jumped = try await identifiers(agent: .claudeCode, items: finishedItems, running: false, jumpTo: "c1")

        #expect(stay.contains("AgentStatusCard.row.task-A"))
        #expect(!stay.contains { $0.contains("rg Retry-After") })
        #expect(jumped.contains { $0.contains("rg Retry-After") })
    }
}
