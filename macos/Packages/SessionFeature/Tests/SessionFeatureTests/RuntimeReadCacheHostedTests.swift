import AppKit
import AgentDomain
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeReadCacheHostedTests {
    @Test func anOpenRowCanRecoverItsActivitiesAfterOtherRowsUseTheDetailCache() async throws {
        let projected = try await projectedConversation()
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        _ = NSApplication.shared
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let hosting = NSHostingView(rootView: EntriesHost(viewModel: projected))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.close() }
        try await waitForWork(in: hosting)

        try await readOtherRows(projected)
        let recovered = try await recoverWork(in: hosting)

        #expect(recovered, "一度開いた作業は、詳細キャッシュが入れ替わっても再読込して表示できる")
    }

    @Test func anOpenCardShowsAndClearsADetailErrorWithoutChangingItsContentVersion() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "実行内容", timestamp: started, attachments: []),
            .commandExecution(id: "work", command: "echo detail", output: "待機中",
                timestamp: started, completedAt: nil, intent: nil),
        ], running: true)
        try await pair.projected.loadRuntimeCardRows("input")
        let rowID = try #require(pair.projected.runtimeChatRead.cards["input"]?.rows.rows.first?.id)
        try await pair.projected.loadRuntimeCardEntries("input", rowID: rowID)

        let visible = try await withHosted(transcript(pair.projected)) { hosting in
            try #require(try await waitForLabel("echo detail", in: hosting))
            pair.projected.runtimeChatRead.cards["input"]?.error = "詳細の読み込みに失敗しました"
            try #require(try await waitForLabel("詳細の読み込みに失敗しました", in: hosting))
            pair.projected.runtimeChatRead.cards["input"]?.error = nil
            try #require(try await waitForAbsentLabel("詳細の読み込みに失敗しました", in: hosting))
            return try await waitForLabel("echo detail", in: hosting)
        }

        #expect(visible)
    }

    @Test func replacingTranscriptCallbacksUpdatesTheActualRestartAndCloseButtons() async throws {
        let sessionID = SessionID()
        let pair = try await projected(items: [
            .error(id: "launch-error-\(sessionID.rawValue)", message: "起動できませんでした", timestamp: .distantPast),
        ], sessionID: sessionID)
        var received: [String] = []
        let visible = try await withHosted(CallbackHost(viewModel: pair.projected, marker: "初期表示")) { hosting in
            try #require(try await waitForLabel("起動できませんでした", in: hosting))
            try #require(try await waitForAbsentIdentifier("ChatLaunchFailure.restart", in: hosting))
            hosting.rootView = CallbackHost(viewModel: pair.projected, marker: "最初の操作先",
                restart: { received.append("first-restart") }, close: { received.append("first-close") })
            try await press(identifier: "ChatLaunchFailure.restart", in: hosting)
            try await press(identifier: "ChatLaunchFailure.close", in: hosting)
            hosting.rootView = CallbackHost(viewModel: pair.projected, marker: "最新の操作先",
                restart: { received.append("latest-restart") }, close: { received.append("latest-close") })
            try #require(try await waitForLabel("最新の操作先", in: hosting))
            try await press(identifier: "ChatLaunchFailure.restart", in: hosting)
            try await press(identifier: "ChatLaunchFailure.close", in: hosting)
            hosting.rootView = CallbackHost(viewModel: pair.projected, marker: "操作なし")
            try #require(try await waitForAbsentIdentifier("ChatLaunchFailure.restart", in: hosting))
            return try await waitForAbsentIdentifier("ChatLaunchFailure.close", in: hosting)
        }

        #expect(visible)
        #expect(received == ["first-restart", "first-close", "latest-restart", "latest-close"])
    }

    @Test func cursorCommandDetailsUseTheInputThatOwnsTheCommandGroup() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let pair = try await projected(items: [
            .userMessage(id: "cursor-input", text: "実行して", timestamp: started, attachments: []),
            .commandExecution(id: "cursor-command", command: "echo cursor", output: "Cursor の実行出力",
                timestamp: started, completedAt: nil, intent: nil),
        ], agent: .cursor, running: true)

        let visible = try await withHosted(transcript(pair.projected)) { hosting in
            try await waitForLabel("Cursor の実行出力", in: hosting)
        }

        #expect(visible)
    }

    @Test func aNewDigestShowsTheNewPreviewUntilTheUserReopensTheFullOutput() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "長い実行出力", timestamp: started, attachments: []),
            .commandExecution(id: "large", command: "printf content",
                output: "OLD_OUTPUT_TOKEN\n" + String(repeating: "output line\n", count: 2_000),
                timestamp: started, completedAt: nil, intent: nil),
        ], running: true)
        let oldReference = try await reference(pair.source, inputID: "input", actionID: "large")
        _ = try await pair.projected.openRuntimeItem(oldReference)
        var changed = pair.source.makeRuntimeSnapshot()
        changed.transcript[1] = .commandExecution(id: "large", command: "printf content",
            output: "NEW_OUTPUT_TOKEN\n" + String(repeating: "changed line\n", count: 2_000),
            timestamp: started, completedAt: nil, intent: nil)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        let newReference = try await reference(updated, inputID: "input", actionID: "large")
        pair.projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        let visible = try await withHosted(RuntimeChatItemReferenceView(reference: oldReference,
            viewModel: pair.projected, isActionDetail: true)) { hosting in
            try #require(try await waitForLabel("OLD_OUTPUT_TOKEN", in: hosting))
            hosting.rootView = RuntimeChatItemReferenceView(reference: newReference,
                viewModel: pair.projected, isActionDetail: true)
            try #require(try await waitForLabel("NEW_OUTPUT_TOKEN", in: hosting))
            try await press(identifier: "ChatTranscript.showFullItem", in: hosting)
            try #require(try await waitForAbsentIdentifier("ChatTranscript.showFullItem", in: hosting))
            return elements(in: hosting).contains { $0.text.contains("NEW_OUTPUT_TOKEN") }
                && !elements(in: hosting).contains { $0.text.contains("OLD_OUTPUT_TOKEN") }
        }

        #expect(visible)
    }

    @Test func aRevealedActionKeepsItsManualDisclosureAcrossStreamingAndRowPageRoundTrips() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = (0..<9).map { AgentTaskItem(id: "stage-\($0)", title: "工程 \($0)", status: $0 == 0 ? .inProgress : .pending) }
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "工程ごとの実行", timestamp: started, attachments: []),
            .taskList(id: "tasks", tasks: tasks, timestamp: started),
            .commandExecution(id: "live-command", command: "echo live", output: "最初の出力",
                timestamp: started, completedAt: nil, intent: nil),
        ], running: true)
        var changed = pair.source.makeRuntimeSnapshot()
        changed.transcript[2] = .commandExecution(id: "live-command", command: "echo live", output: "更新された出力",
            timestamp: started, completedAt: nil, intent: nil)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }

        let request = SessionRuntimeChatReadRevealTarget(inputID: "input", cardID: "status-card-input",
            rowID: "task-stage-0", entryID: "live-command", itemID: "live-command")
        let visible = try await withHosted(CardHost(viewModel: pair.projected, revealRequest: request, revealSerial: 1)) { hosting in
            try #require(try await waitForLabel("最初の出力", in: hosting))
            pair.projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }
            try pair.projected.applyRuntimeOverview(updated.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try #require(try await waitForLabel("更新された出力", in: hosting))
            try await pair.projected.loadRuntimeCardRows("input", navigation: .next)
            try #require(try await waitForAbsentIdentifier("AgentStatusCard.row.task-stage-0", in: hosting))
            try await pair.projected.loadRuntimeCardRows("input", navigation: .first)
            try #require(try await waitForLabel("更新された出力", in: hosting))
            try await press(label: "echo live", in: hosting)
            try #require(try await waitForAbsentLabel("更新された出力", in: hosting))
            try await pair.projected.loadRuntimeCardRows("input", navigation: .next)
            try #require(try await waitForAbsentIdentifier("AgentStatusCard.row.task-stage-0", in: hosting))
            try await pair.projected.loadRuntimeCardRows("input", navigation: .first)
            try await pair.projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")
            try #require(try await waitForLabel("echo live", role: NSAccessibility.Role.button.rawValue, in: hosting))
            return !elements(in: hosting).contains { $0.text.contains("更新された出力") }
        }

        #expect(visible)
    }

    @Test func unrelatedOutputDoesNotResetThePageOfAnOlderCursorCommandGroup() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let commands = (0..<120).map { number in
            ChatItem.commandExecution(id: "group-\(number)", command: "echo group-\(number)", output: "結果 \(number)",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)
        }
        let pair = try await projected(items: [.userMessage(id: "old-input", text: "先の実行", timestamp: started,
            attachments: [], turnEnd: ChatTurnEnd(outcome: .completed, at: started.addingTimeInterval(2)))] + commands,
            agent: .cursor)
        var changed = pair.source.makeRuntimeSnapshot()
        changed.transcript += [
            .userMessage(id: "new-input", text: "次の依頼", timestamp: started.addingTimeInterval(3), attachments: []),
            .agentMessage(id: "new-answer", text: "新しいターンの返答", timestamp: started.addingTimeInterval(4)),
        ]
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }

        let visible = try await withHosted(transcript(pair.projected)) { hosting in
            try await press(label: "ツール実行", in: hosting)
            try #require(try await waitForLabel("Bash、echo group-0、1 行", in: hosting))
            try await press(label: "さらに表示", in: hosting)
            try #require(try await waitForLabel("Bash、echo group-50、1 行", in: hosting))
            pair.projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }
            try pair.projected.applyRuntimeOverview(updated.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try #require(try await waitForLabel("新しいターンの返答", in: hosting))
            return elements(in: hosting).contains { $0.label == "Bash、echo group-50、1 行" }
                && !elements(in: hosting).contains { $0.label == "Bash、echo group-0、1 行" }
        }

        #expect(visible)
    }

    @Test func aCursorGroupsOwnBodyUpdateAndInsertionKeepItsManualDetailPage() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let commands = (0..<120).map { number in
            ChatItem.commandExecution(id: "group-\(number)", command: "echo group-\(number)", output: "結果 \(number)",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)
        }
        let pair = try await projected(items: [.userMessage(id: "input", text: "実行", timestamp: started,
            attachments: [], turnEnd: .init(outcome: .completed, at: started.addingTimeInterval(2)))] + commands,
            agent: .cursor)

        let preserved = try await withHosted(transcript(pair.projected)) { hosting in
            try await press(label: "ツール実行", in: hosting)
            try #require(try await waitForLabel("Bash、echo group-0、1 行", in: hosting))
            try await press(label: "さらに表示", in: hosting)
            try #require(try await waitForLabel("Bash、echo group-50、1 行", in: hosting))
            try await press(label: "echo group-60", in: hosting)
            try #require(try await waitForLabel("結果 60", in: hosting))
            var changed = pair.source.makeRuntimeSnapshot()
            changed.transcript[61] = .commandExecution(id: "group-60", command: "echo group-60", output: "GROUP_UPDATED_BODY",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)
            changed.transcript.insert(.commandExecution(id: "inserted", command: "echo inserted", output: "挿入",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil), at: 11)
            changed.transcriptRevision = 8
            try pair.source.applyRuntimeSnapshot(changed)
            try pair.projected.applyRuntimeOverview(pair.source.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try #require(try await waitForLabel("GROUP_UPDATED_BODY", in: hosting))
            let rows = elements(in: hosting).filter { $0.role == NSAccessibility.Role.button.rawValue && $0.label.hasPrefix("Bash、echo group-") }
            return Set(rows.map(\.label)) == Set((50..<100).map { "Bash、echo group-\($0)、1 行" })
        }
        #expect(preserved)
    }

    @Test func localEntryPagingKeepsAllVisibleItemsDuringAppendAndCanReturnToLatest() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let reasoning = (0..<120).map { ChatItem.reasoning(id: "reason-\($0)", text: "作業記録 \($0)", timestamp: started) }
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "作業記録を表示", timestamp: started, attachments: []),
            .taskList(id: "tasks", tasks: [.init(id: "stage-0", title: "記録", status: .inProgress)], timestamp: started),
        ] + reasoning)
        try await pair.projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")

        let preserved = try await withHosted(EntriesHost(viewModel: pair.projected)) { hosting in
            try #require(try await waitForReasoningIDs(Set((90..<120).map { "reason-\($0)" }), in: hosting))
            try await press(identifier: "AgentStatusCard.showMore", in: hosting)
            let manualIDs = Set((70..<90).map { "reason-\($0)" })
            try #require(try await waitForReasoningIDs(manualIDs, in: hosting))
            var changed = pair.source.makeRuntimeSnapshot()
            changed.transcript[82] = .reasoning(id: "reason-80", text: "更新された作業記録 80", timestamp: started)
            changed.transcript.append(.reasoning(id: "reason-120", text: "作業記録 120", timestamp: started))
            changed.transcriptRevision = 8
            try pair.source.applyRuntimeSnapshot(changed)
            try pair.projected.applyRuntimeOverview(pair.source.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try #require(try await waitForLabel("更新された作業記録 80", in: hosting))
            try #require(try await waitForReasoningIDs(manualIDs, in: hosting))
            try await press(label: "最新の作業に戻る", in: hosting)
            return try await waitForReasoningIDs(Set((91..<121).map { "reason-\($0)" }), in: hosting)
        }
        #expect(preserved)
    }

    @Test func heavyEntryPagingVisitsEachPrecedingItemWithoutSkippingTheMiddle() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let reasoning = (0..<120).map {
            ChatItem.reasoning(id: "reason-\($0)", text: "# 作業記録 \($0)\n\n" + String(repeating: "x", count: 2_000), timestamp: started)
        }
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "重い作業記録を表示", timestamp: started, attachments: []),
            .taskList(id: "tasks", tasks: [.init(id: "stage-0", title: "記録", status: .inProgress)], timestamp: started),
        ] + reasoning)
        try await pair.projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")
        try await pair.projected.loadRuntimeCardEntries("input", rowID: "task-stage-0", next: true)
        try #require(pair.projected.runtimeChatRead.cards["input"]?.entries["task-stage-0"]?.entries.first?.id == "reason-20")
        try #require(pair.projected.runtimeChatRead.cards["input"]?.entries["task-stage-0"]?.entries.last?.id == "reason-69")

        let visited = try await withHosted(EntriesHost(viewModel: pair.projected)) { hosting in
            try #require(try await waitForReasoningIDs(["reason-69"], in: hosting))
            try await press(identifier: "AgentStatusCard.showMore", in: hosting)
            try #require(try await waitForReasoningIDs(["reason-68"], in: hosting))
            try #require(pair.projected.runtimeChatRead.cards["input"]?.entries["task-stage-0"]?.entries.last?.id == "reason-68")
            try await press(identifier: "AgentStatusCard.showMore", in: hosting)
            return try await waitForReasoningIDs(["reason-67"], in: hosting)
        }
        #expect(visited)
        #expect(pair.projected.runtimeChatRead.cards["input"]?.entries["task-stage-0"]?.entries.last?.id == "reason-67")
    }

    private func waitForReasoningIDs(_ expected: Set<String>, in hosting: NSView) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            let nodes = elements(in: hosting)
            let actual = Set((0..<121).filter { number in
                let text = "作業記録 \(number)"
                return nodes.contains { $0.label.hasSuffix(text) || $0.value.hasSuffix(text) }
            }.map { "reason-\($0)" })
            if actual == expected { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func completedTaskRowsRemainAvailableAcrossBothDirectionsOfTheBoundedWindow() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let pair = try await projected(items: manyCompletedCards(started))

        let walked = try await withHosted(transcript(pair.projected)) { hosting in
            try await walkCompletedCardRows(pair.projected, in: hosting)
        }

        #expect(walked == Set((0..<33).map { "AgentStatusCard.row.outside-command-\($0)" }))
        let loadedInputs = pair.projected.runtimeChatRead.page?.blocks.compactMap { block -> String? in
            if case .item(.inline(.userMessage(let id, _, _, _, _))) = block.content { id } else { nil }
        } ?? []
        #expect(loadedInputs.count == 33)
        #expect(Set(loadedInputs) == Set((0..<33).map { "input-\($0)" }))
    }

    @Test func anOpenActionCanReloadItsDetailAfterOtherActionsUseTheDetailCache() async throws {
        let projected = try await projectedConversation()
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")
        try await projected.loadRuntimeActionItems("input", actionID: "command-0")

        let visible = try await withHosted(ActionHost(viewModel: projected)) { hosting in
            try #require(try await waitForLabel("工程 0 の結果", in: hosting))
            try await projected.loadRuntimeActionItems("input", actionID: "command-1")
            try await projected.loadRuntimeActionItems("input", actionID: "command-2")
            return try await recoverWork(in: hosting,
                retryID: "AgentStatusCard.reloadActionItems.command-0", retryLabel: "詳細を読み込む", label: "工程 0 の結果")
        }

        #expect(visible)
    }

    private func manyCompletedCards(_ started: Date) -> [ChatItem] {
        (0..<33).flatMap { number -> [ChatItem] in
            [.userMessage(id: "input-\(number)", text: "依頼 \(number)", timestamp: started,
                attachments: [], turnEnd: ChatTurnEnd(outcome: .completed, at: started.addingTimeInterval(2))),
             .commandExecution(id: "command-\(number)", command: "echo \(number)", output: "結果",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)]
        }
    }

    private struct ActionHost: View {
        @Bindable var viewModel: ChatSessionViewModel
        var body: some View {
            if let cache = viewModel.runtimeChatRead.cards["input"],
               let summary = cache.entries["task-stage-0"]?.entries.compactMap({ entry -> SessionRuntimeActionSummary? in
                   if case .action(let summary) = entry { summary } else { nil }
               }).first {
                AgentStatusActionRow(action: summary.action, scale: 1, isTimelineVisible: false, startsOpen: true,
                    runtime: RuntimeStatusCardPresentation(inputID: "input", cache: cache, viewModel: viewModel))
            }
        }
    }

    @Test func aCompletedTaskOpensWhenTheJumpedReasoningBodyIsDeferred() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "大きな説明を残す", timestamp: started, attachments: [],
                turnEnd: ChatTurnEnd(outcome: .completed, at: started.addingTimeInterval(30))),
            .taskList(id: "tasks-start", tasks: [AgentTaskItem(id: "A", title: "説明する", status: .inProgress)], timestamp: started),
            .reasoning(id: "giant-thought", text: "DEFERRED_REASONING_TOKEN " + String(repeating: "説明の本文。", count: 2_000), timestamp: started),
            .taskList(id: "tasks-end", tasks: [AgentTaskItem(id: "A", title: "説明する", status: .completed)],
                timestamp: started.addingTimeInterval(20)),
        ])
        let request = SessionRuntimeChatReadRevealTarget(inputID: "input", cardID: "status-card-input",
            rowID: "task-A", entryID: "giant-thought", itemID: "giant-thought")

        let visible = try await withHosted(CardHost(viewModel: pair.projected, revealRequest: request, revealSerial: 1)) { hosting in
            try #require(try await waitForLabel("DEFERRED_REASONING_TOKEN", in: hosting))
            return elements(in: hosting).contains { $0.role == NSAccessibility.Role.button.rawValue && $0.label == "全文を表示" }
        }

        #expect(visible)
    }

    private struct CallbackHost: View {
        let viewModel: ChatSessionViewModel
        let marker: String
        var restart: (() -> Void)? = nil
        var close: (() -> Void)? = nil
        var body: some View {
            VStack {
                Text(marker)
                ChatTranscriptView(viewModel: viewModel,
                    onLaunchFailureRestart: restart, onLaunchFailureClose: close)
            }
        }
    }

    private struct CardHost: View {
        @Bindable var viewModel: ChatSessionViewModel
        var revealRequest: SessionRuntimeChatReadRevealTarget? = nil
        var revealSerial = 0
        var body: some View {
            if let summary = viewModel.runtimeChatRead.page?.blocks.compactMap({ block -> SessionRuntimeCardSummary? in
                if case .card(let summary) = block.content { summary } else { nil }
            }).first {
                RuntimeStatusCardView(viewModel: viewModel, summary: summary, cache: viewModel.runtimeChatRead.cards[summary.inputID], isNarrow: false,
                    revealRequest: revealRequest, revealSerial: revealSerial,
                    itemActions: RuntimeChatItemActions(restart: nil, close: nil, isRestarting: false))
                    .equatable()
            }
        }
    }

    private func transcript(_ projected: ChatSessionViewModel) -> some View {
        RuntimeChatTranscriptView(viewModel: projected, requestedScrollTarget: .constant(nil),
            currentInputPositionID: .constant(nil), contentMaxWidth: nil, bottomMargin: 0,
            context: .single, showsThinkingIndicator: true,
            itemActions: RuntimeChatItemActions(restart: nil, close: nil, isRestarting: false))
            .environment(\.locale, Locale(identifier: "ja"))
    }

    private func projected(items: [ChatItem], agent: AgentKind = .codex, running: Bool = false, sessionID: SessionID = SessionID())
        async throws -> (projected: ChatSessionViewModel, source: ChatSessionViewModel) {
        var snapshot = SessionRuntimeChatSnapshot(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            agentRef: .builtin(agent), workingDirectory: "/workspace")
        snapshot.transcript = items
        snapshot.transcriptRevision = 7
        snapshot.status = running ? .running : .idle
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeSupportsChatReadModel = true
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeContent()
        return (projected, source)
    }

    private func reference(_ source: ChatSessionViewModel, inputID: String, actionID: String) async throws -> SessionRuntimeChatItemReference {
        let response = try await source.runtimeChatReadContent(for: .init(sessionID: source.id, executionID: source.executionID,
            target: .chatActionItems(inputID: inputID, actionID: actionID, cursor: nil)))
        guard case .actionItemsPage(let page) = response else { throw SessionRuntimeContentError.invalidRequest }
        return try #require(page.items.first)
    }

    private func withHosted<Content: View, Value>(_ content: Content,
        operation: (NSHostingView<Content>) async throws -> Value) async throws -> Value {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: "AXEnhancedUserInterface")?.takeUnretainedValue()
        NSApp.perform(setter, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        defer { NSApp.perform(setter, with: previous, with: "AXEnhancedUserInterface") }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = hosting
        window.orderBack(nil)
        defer { capture(hosting); window.close() }
        return try await operation(hosting)
    }

    private func press(identifier: String, in hosting: NSView) async throws {
        try #require(try await waitForIdentifier(identifier, in: hosting))
        let element = try #require(elements(in: hosting).first { $0.id == identifier })
        let action = NSSelectorFromString("accessibilityPerformPress")
        try #require(element.object.responds(to: action))
        _ = element.object.perform(action)
    }

    private func press(label: String, in hosting: NSView) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            if let element = elements(in: hosting).first(where: { $0.role == NSAccessibility.Role.button.rawValue && $0.text.contains(label) }) {
                _ = element.object.perform(NSSelectorFromString("accessibilityPerformPress"))
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("操作できるボタンが見つからない: \(label)")
        throw SessionRuntimeContentError.notFound
    }

    private func waitForIdentifier(_ id: String, in hosting: NSView) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            if elements(in: hosting).contains(where: { $0.id == id }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitForAbsentIdentifier(_ id: String, in hosting: NSView) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            if !elements(in: hosting).contains(where: { $0.id == id }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitForRuntimeReadIdle(_ projected: ChatSessionViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.isLoading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(!projected.runtimeChatRead.isLoading)
    }

    private struct RenderedCardStage: Equatable {
        let firstID: String
        let lastID: String
        let rows: Set<String>
    }

    private func waitForCompleteCardStage(_ projected: ChatSessionViewModel, in hosting: NSView,
                                          after previous: RenderedCardStage? = nil) async throws -> RenderedCardStage {
        let deadline = ContinuousClock.now + .seconds(3)
        var complete: RenderedCardStage?
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            let state = projected.runtimeChatRead
            if state.control.renderedSpans.count == 1, let span = state.control.renderedSpans.values.first,
               let blocks = state.page?.blocks,
               let first = blocks.firstIndex(where: { $0.id == span.firstID }),
               let last = blocks.firstIndex(where: { $0.id == span.lastID }), first <= last {
                let displayed = Array(blocks[first...last])
                let expectedRows = Set(displayed.compactMap { block -> String? in
                    guard case .card(let card) = block.content else { return nil }
                    return "AgentStatusCard.row.outside-command-" + card.inputID.replacingOccurrences(of: "input-", with: "")
                })
                let expectedInputs = displayed.compactMap { block -> String? in
                    if case .item(.inline(.userMessage(_, let text, _, _, _))) = block.content { text } else { nil }
                }
                let nodes = elements(in: hosting)
                let actualRows = Set(nodes.map(\.id).filter { $0.hasPrefix("AgentStatusCard.row.outside-command-") })
                let stage = RenderedCardStage(firstID: span.firstID, lastID: span.lastID, rows: actualRows)
                try #require(expectedRows.count <= 24, "各表示段は共通8段予算の最大24カード以内")
                let inputsPresent = expectedInputs.allSatisfy { text in nodes.contains { $0.label == text || $0.value == text } }
                if !expectedRows.isEmpty, actualRows == expectedRows, inputsPresent,
                   previous == nil || stage.firstID != previous?.firstID || stage.lastID != previous?.lastID {
                    complete = stage
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try #require(complete, "表示中の全カードに実タスク行と入力本文が揃う必要があります")
    }

    private func walkCompletedCardRows(_ projected: ChatSessionViewModel, in hosting: NSView) async throws -> Set<String> {
        try await waitForRuntimeReadIdle(projected)
        var stage = try await waitForCompleteCardStage(projected, in: hosting)
        try #require(stage.rows.contains("AgentStatusCard.row.outside-command-32"), "初期表示は最新入力に到達")
        var visited = stage.rows
        for _ in 0..<20 {
            if stage.rows.contains("AgentStatusCard.row.outside-command-0") { break }
            try await waitForRuntimeReadIdle(projected)
            try await press(identifier: "ChatTranscript.loadEarlier", in: hosting)
            stage = try await waitForCompleteCardStage(projected, in: hosting, after: stage)
            visited.formUnion(stage.rows)
        }
        try #require(stage.rows.contains("AgentStatusCard.row.outside-command-0"), "実UIで最古入力へ到達")
        for _ in 0..<20 {
            if stage.rows.contains("AgentStatusCard.row.outside-command-32") { break }
            try await waitForRuntimeReadIdle(projected)
            try await press(identifier: "ChatTranscript.loadNewer", in: hosting)
            stage = try await waitForCompleteCardStage(projected, in: hosting, after: stage)
            visited.formUnion(stage.rows)
        }
        try #require(stage.rows.contains("AgentStatusCard.row.outside-command-32"), "実UIで最新入力へ戻る")
        return visited
    }

    private func waitForAbsentLabel(_ text: String, in hosting: NSView) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            if !elements(in: hosting).contains(where: { $0.text.contains(text) }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitForLabel(_ text: String, role: String? = nil, in hosting: NSView) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            if elements(in: hosting).contains(where: { $0.text.contains(text) && (role == nil || $0.role == role) }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test(arguments: [false, true])
    func actionEntryBoundariesKeepBindingsFreshDetailsErrorsAndRoutes(useParentBinding: Bool) async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = SessionID()
        let pair = try await projected(items: [
            .userMessage(id: "input", text: "行の更新を確認", timestamp: started, attachments: []),
            .taskList(id: "tasks", tasks: [.init(id: "stage-0", title: "工程", status: .inProgress)], timestamp: started),
            .commandExecution(id: "first", command: "echo first", output: "FIRST_BODY", timestamp: started,
                completedAt: started.addingTimeInterval(1), intent: nil),
            .commandExecution(id: "second", command: "echo second", output: "OLD_SECOND_BODY", timestamp: started,
                completedAt: started.addingTimeInterval(1), intent: nil),
            .error(id: "launch-error-\(sessionID.rawValue)", message: "起動できませんでした", timestamp: started),
        ], sessionID: sessionID)
        try await pair.projected.loadRuntimeCardEntries("input", rowID: "task-stage-0")
        var received: [String] = []
        let errorText = URLError(.networkConnectionLost).localizedDescription

        let usable = try await withHosted(ActionEntryBoundaryHost(viewModel: pair.projected, useParentBinding: useParentBinding)) { hosting in
            try #require(try await waitForLabel("echo first", in: hosting))
            var metadata = pair.source.makeRuntimeSnapshot()
            metadata.transcript[1] = .taskList(id: "tasks", tasks: [.init(id: "stage-0", title: "更新した工程", status: .inProgress)], timestamp: started)
            metadata.transcriptRevision = 8
            try pair.source.applyRuntimeSnapshot(metadata)
            try pair.projected.applyRuntimeOverview(pair.source.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try await press(label: "echo first", in: hosting)
            try #require(try await waitForLabel("FIRST_BODY", in: hosting))
            try await press(label: "echo first", in: hosting)
            try #require(try await waitForAbsentLabel("FIRST_BODY", in: hosting))

            var changed = pair.source.makeRuntimeSnapshot()
            changed.transcript[3] = .commandExecution(id: "second", command: "echo second", output: "LATEST_SECOND_BODY",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)
            changed.transcriptRevision = 9
            try pair.source.applyRuntimeSnapshot(changed)
            try pair.projected.applyRuntimeOverview(pair.source.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            pair.projected.runtimeContentLoader = { request in
                switch request.target {
                case .chatActionItems, .chatActionItemsFrom: throw URLError(.networkConnectionLost)
                default: return try await pair.source.runtimeChatReadContent(for: request)
                }
            }
            try await press(label: "echo second", in: hosting)
            try #require(try await waitForLabel(errorText, in: hosting))
            pair.projected.runtimeContentLoader = { try await pair.source.runtimeChatReadContent(for: $0) }
            try await press(label: "詳細を読み込む", in: hosting)
            try #require(try await waitForLabel("LATEST_SECOND_BODY", in: hosting))
            try #require(try await waitForAbsentLabel(errorText, in: hosting))

            var latest = pair.source.makeRuntimeSnapshot()
            latest.transcript[3] = .commandExecution(id: "second", command: "echo second", output: "FINAL_SECOND_BODY",
                timestamp: started, completedAt: started.addingTimeInterval(1), intent: nil)
            latest.transcriptRevision = 10
            try pair.source.applyRuntimeSnapshot(latest)
            try pair.projected.applyRuntimeOverview(pair.source.makeRuntimeOverview())
            try await pair.projected.refreshRuntimeContent()
            try #require(try await waitForLabel("FINAL_SECOND_BODY", in: hosting))
            try #require(try await waitForAbsentLabel("LATEST_SECOND_BODY", in: hosting))
            try #require(try await waitForAbsentIdentifier("ChatLaunchFailure.restart", in: hosting))
            let actions = RuntimeChatItemActions(restart: { received.append("restart") },
                close: { received.append("close") }, isRestarting: false)
            hosting.rootView = ActionEntryBoundaryHost(viewModel: pair.projected, useParentBinding: useParentBinding, actions: actions)
            try await press(identifier: "ChatLaunchFailure.restart", in: hosting)
            try await press(identifier: "ChatLaunchFailure.close", in: hosting)
            hosting.rootView = ActionEntryBoundaryHost(viewModel: pair.projected, useParentBinding: useParentBinding)
            try #require(try await waitForAbsentIdentifier("ChatLaunchFailure.restart", in: hosting))
            try #require(try await waitForAbsentIdentifier("ChatLaunchFailure.close", in: hosting))
            try await press(label: "echo second", in: hosting)
            try #require(try await waitForAbsentLabel("FINAL_SECOND_BODY", in: hosting))
            return try await waitForLabel("echo second", in: hosting)
        }
        #expect(usable)
        #expect(received == ["restart", "close"])
    }

    private struct ActionEntryBoundaryHost: View {
        @Bindable var viewModel: ChatSessionViewModel
        let useParentBinding: Bool
        var actions: RuntimeChatItemActions? = nil
        @State private var disclosure = AgentStatusCardDisclosure()

        var body: some View {
            if let cache = viewModel.runtimeChatRead.cards["input"] {
                RuntimeCardEntriesView(presentation: RuntimeStatusCardPresentation(inputID: "input", cache: cache,
                    viewModel: viewModel, itemActions: actions), rowID: "task-stage-0", scale: 1,
                    isTimelineVisible: false, actionDisclosure: useParentBinding ? $disclosure : nil)
            }
        }
    }

    private struct EntriesHost: View {
        @Bindable var viewModel: ChatSessionViewModel
        var body: some View {
            if let cache = viewModel.runtimeChatRead.cards["input"] {
                RuntimeCardEntriesView(presentation: RuntimeStatusCardPresentation(inputID: "input",
                    cache: cache, viewModel: viewModel), rowID: "task-stage-0", scale: 1, isTimelineVisible: false)
            }
        }
    }

    private func projectedConversation() async throws -> ChatSessionViewModel {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        var items: [ChatItem] = [.userMessage(id: "input", text: "工程ごとに作業", timestamp: started, attachments: [])]
        for index in 0..<9 {
            let tasks = (0..<9).map { number in
                AgentTaskItem(id: "stage-\(number)", title: "工程 \(number)",
                    status: number == index ? .inProgress : (number < index ? .completed : .pending))
            }
            items.append(.taskList(id: "tasks-\(index)", tasks: tasks,
                timestamp: started.addingTimeInterval(Double(index * 2))))
            items.append(.commandExecution(id: "command-\(index)", command: "echo row-\(index)", output: "工程 \(index) の結果",
                timestamp: started.addingTimeInterval(Double(index * 2 + 1)),
                completedAt: started.addingTimeInterval(Double(index * 2 + 2)), intent: nil))
        }
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: started,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
        snapshot.transcriptRevision = 7
        snapshot.status = .running
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeSupportsChatReadModel = true
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeContent()
        try await projected.loadRuntimeCardRows("input", navigation: .first)
        return projected
    }

    private func readOtherRows(_ projected: ChatSessionViewModel) async throws {
        for index in 1..<9 { try await projected.loadRuntimeCardEntries("input", rowID: "task-stage-\(index)") }
    }

    private func waitForWork(in hosting: NSView) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !elements(in: hosting).contains(where: { $0.text.contains("echo row-0") }) {
            try #require(ContinuousClock.now < deadline, "作業の行が表示されること")
            try await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
    }

    private func recoverWork(in hosting: NSView,
        retryID: String = "AgentStatusCard.reloadEntries.task-stage-0", retryLabel: String? = nil, label: String = "echo row-0") async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        var pressed = false
        while ContinuousClock.now < deadline {
            hosting.layoutSubtreeIfNeeded()
            let current = elements(in: hosting)
            if pressed, current.contains(where: { $0.text.contains(label) }) { return true }
            if !pressed, let retry = current.first(where: { $0.id == retryID || (retryLabel != nil && $0.role == NSAccessibility.Role.button.rawValue && $0.label == retryLabel) }) {
                let press = NSSelectorFromString("accessibilityPerformPress")
                if retry.object.responds(to: press) { _ = retry.object.perform(press); pressed = true }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private struct HostedElement {
        let object: NSObject
        let id: String
        let label: String
        let value: String
        let role: String
        var text: String { label + "\n" + value }
    }

    private func elements(in root: NSObject) -> [HostedElement] {
        var visited = Set<ObjectIdentifier>()
        var result: [HostedElement] = []
        func visit(_ object: NSObject) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            let idSelector = NSSelectorFromString("accessibilityIdentifier")
            let labelSelector = NSSelectorFromString("accessibilityLabel")
            let id = object.responds(to: idSelector) ? object.perform(idSelector)?.takeUnretainedValue() as? String : nil
            let label = object.responds(to: labelSelector) ? object.perform(labelSelector)?.takeUnretainedValue() as? String : nil
            let roleSelector = NSSelectorFromString("accessibilityRole")
            let role = object.responds(to: roleSelector) ? object.perform(roleSelector)?.takeUnretainedValue() as? String : nil
            let valueSelector = NSSelectorFromString("accessibilityValue")
            let rawValue = object.responds(to: valueSelector) ? object.perform(valueSelector)?.takeUnretainedValue() : nil
            let value = (rawValue as? String) ?? (rawValue as? NSAttributedString)?.string ?? ""
            result.append(HostedElement(object: object, id: id ?? "", label: label ?? "", value: value, role: role ?? ""))
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [NSObject] {
                values.forEach(visit)
            }
            if let view = object as? NSView { view.subviews.forEach(visit) }
        }
        visit(root)
        return result
    }
    private func capture(_ hosting: NSView) {
        guard let directory = ProcessInfo.processInfo.environment["PHLOX_HOSTED_DIAGNOSTIC_DIR"] else { return }
        let folder = URL(fileURLWithPath: directory)
        let name = "host-" + UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let nodes = elements(in: hosting).map {
                ["id": $0.id, "role": $0.role, "label": String($0.label.prefix(1_024)), "value": String($0.value.prefix(1_024))]
            }
            try JSONSerialization.data(withJSONObject: nodes, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent(name + ".json"))
            let ownership = "用途: Hosted回帰のAX/描画診断。所有 /root/semantic_ui。PID \(ProcessInfo.processInfo.processIdentifier)。実行 \(ProcessInfo.processInfo.arguments.first ?? "unknown")。\n"
            try ownership.write(to: folder.appendingPathComponent("ownership-\(ProcessInfo.processInfo.processIdentifier).txt"), atomically: true, encoding: .utf8)
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
            }
        } catch { print("Hosted診断の保存に失敗: \(error)") }
    }

}
