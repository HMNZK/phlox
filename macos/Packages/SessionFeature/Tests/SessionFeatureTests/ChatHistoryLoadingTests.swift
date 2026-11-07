import AgentDomain
import AppKit
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("チャット履歴のスクロール読み込み", .serialized)
@MainActor
struct ChatHistoryLoadingTests {
    @Test func scrollInputRequiresTopDirectionAndOwnViewport() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let document = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        scroll.documentView = document
        let window = makeWindow(scroll)
        defer { window.close() }
        var requests = 0
        var releases = 0
        let bridge = ChatAutoFollowScrollEventBridge(controller: ChatAutoFollowController(), onScrollPastTop: { requests += 1 }, onScrollReleased: { releases += 1 })
        bridge.attach(to: scroll)
        defer { bridge.detach() }
        let event = HistoryWheelEvent()
        event.testWindow = window
        event.testLocation = NSPoint(x: 150, y: 100)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        bridge.handleScrollWheel(event)
        #expect(requests == 0)
        scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(requests == 0, "レイアウト・プログラムによる先頭移動では追加しない")
        event.delta = -10
        bridge.handleScrollWheel(event)
        event.delta = 10
        event.testMomentumPhase = .changed
        bridge.handleScrollWheel(event)
        event.testMomentumPhase = []
        event.testLocation = NSPoint(x: 500, y: 100)
        bridge.handleScrollWheel(event)
        #expect(requests == 0)
        event.testLocation = NSPoint(x: 150, y: 100)
        event.testPhase = .changed
        event.delta = 60
        bridge.handleScrollWheel(event)
        #expect(requests == 0, "観測開始前から続くジェスチャーは引き継がない")
        event.testPhase = .began
        event.delta = 10
        bridge.handleScrollWheel(event)
        event.testPhase = .changed
        event.delta = 49
        bridge.handleScrollWheel(event)
        #expect(requests == 0, "上端での追加スクロールが59ptなら表示しない")
        event.delta = 1
        bridge.handleScrollWheel(event)
        #expect(requests == 1, "60ptで初めてローダーを表示する")
        event.delta = 60
        bridge.handleScrollWheel(event)
        #expect(requests == 1, "同じジェスチャーでは1回だけ追加する")
        #expect(releases == 0, "スクロール中は履歴を追加しない")
        event.testPhase = .ended
        bridge.handleScrollWheel(event)
        bridge.handleScrollWheel(event)
        #expect(releases == 1, "指を離したときに1回だけ追加する")
        event.testPhase = .began
        bridge.handleScrollWheel(event)
        #expect(requests == 2)
        bridge.detach()
        bridge.handleScrollWheel(event)
        #expect(requests == 2)
    }

    @Test func bottomPullRequiresHiddenNewerAndKeepsDetached() throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let document = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        scroll.documentView = document
        let window = makeWindow(scroll)
        defer { window.close() }
        let controller = ChatAutoFollowController()
        controller.userInitiatedJump()
        var tops = 0
        var bottoms = 0
        var releases = 0
        let bridge = ChatAutoFollowScrollEventBridge(
            controller: controller, onScrollPastTop: { tops += 1 }, onScrollPastBottom: { bottoms += 1 },
            onScrollReleased: { releases += 1 }, hasNewerHidden: false
        )
        bridge.attach(to: scroll)
        defer { bridge.detach() }
        let event = HistoryWheelEvent()
        event.testWindow = window
        event.testLocation = NSPoint(x: 150, y: 100)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(controller.isFollowing, "新しい側が隠れていなければ最下部で追従に戻る")
        event.testPhase = .began
        event.delta = -70
        bridge.handleScrollWheel(event)
        #expect(bottoms == 0, "新しい側が隠れていなければ下端では読み込まない")

        controller.userInitiatedJump()
        bridge.update(
            controller: controller, onViewportCenterChanged: { _ in }, onScrollPastTop: { tops += 1 },
            onScrollPastBottom: { bottoms += 1 }, onScrollReleased: { releases += 1 }, hasNewerHidden: true
        )
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        #expect(!controller.isFollowing, "新しい側が隠れている間は最下部でも追従に戻らない")
        event.testPhase = .began
        event.delta = -10
        bridge.handleScrollWheel(event)
        event.testPhase = .changed
        event.delta = -49
        bridge.handleScrollWheel(event)
        #expect(bottoms == 0, "下端での追加スクロールが59ptなら表示しない")
        event.delta = 20
        bridge.handleScrollWheel(event)
        event.delta = -20
        bridge.handleScrollWheel(event)
        #expect(bottoms == 0, "上向きに戻した分は差し引く")
        event.delta = -1
        bridge.handleScrollWheel(event)
        #expect(bottoms == 1, "60ptで初めてローダーを表示する")
        event.delta = -60
        bridge.handleScrollWheel(event)
        #expect(bottoms == 1, "同じジェスチャーでは1回だけ")
        #expect(releases == 0, "スクロール中は読み込まない")
        event.testPhase = .ended
        bridge.handleScrollWheel(event)
        #expect(releases == 1, "指を離したときに1回だけ読み込む")
        event.testPhase = .began
        event.delta = -70
        bridge.handleScrollWheel(event)
        event.testPhase = .cancelled
        bridge.handleScrollWheel(event)
        event.testPhase = .ended
        bridge.handleScrollWheel(event)
        #expect(bottoms == 2)
        #expect(releases == 1, "取り消したジェスチャーでは読み込まない")
        #expect(tops == 0)
    }

    @Test func historyBeyondCapHidesNewerAndLoadsItBack() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let many = (0..<300).map { ChatItem.userMessage(id: "many-\($0)", text: "メッセージ \($0)", timestamp: .distantPast) }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: many, presentationContext: .gridTile))
        let window = makeWindow(host)
        defer { window.close() }
        let cap = TranscriptWindow.maxStages * TranscriptWindow.gridTileDefaultLimit
        try await wait(host) { hiddenCount(host) == 300 - 16 }
        for _ in 0..<3 { try loadEarlier(host) }
        try await wait(host, stage: "上限まで遡る") { hiddenCount(host) == 300 - cap }
        #expect(hiddenNewerCount(host) == 0, "上限までは新しい側を外さない")
        try loadEarlier(host)
        try await wait(host, stage: "上限を超えて遡る") { hiddenCount(host) == 300 - cap - 16 }
        #expect(hiddenNewerCount(host) == 16, "上限を超えて遡った分だけ新しい側を外す")
        #expect(element(host, "ChatTranscript.jumpToLatest") != nil, "新しい側を外している間は最新へ戻るボタンを出す")

        try loadNewer(host)
        try await wait(host, stage: "新しい側を読み込む") { hiddenNewerCount(host) == 0 }
        #expect(hiddenCount(host) == 300 - cap)

        try loadEarlier(host)
        try await wait(host) { hiddenNewerCount(host) == 16 }
        let jump = try #require(element(host, "ChatTranscript.jumpToLatest"))
        let pressed = jump.accessibilityPerformPress()
        #expect(pressed)
        try await wait(host, stage: "最新へ") {
            hiddenNewerCount(host) == 0 && scrollViews(host).first.map(ChatAutoFollowGeometry.isAtBottom) == true
        }
    }

    /// 実行中の見出しだけのカードを外して固定している間に処理が終わると、項目は変わらずにカードだけが消える。
    /// そのとき末尾追従に戻らないと、次に送った入力が窓の外に積まれて描画されない（独立レビュー 6 回目）。
    @Test func pinnedWindowFollowsTailWhenProcessingEndsWithoutNewItems() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let client = HistoryFakeAgentClient()
        let model = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
                                         approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-history-test")
        client.yield(.turnStarted)
        try await wait(NSView(), stage: "実行中") { model.status == .running }
        var items = (0..<300).flatMap { index -> [ChatItem] in
            [.userMessage(id: "u\(index)", text: "入力", timestamp: .distantPast),
             .agentMessage(id: "a\(index)", text: "返答", timestamp: .distantPast)]
        }
        // 1 段の予算を超える最後の入力。作業も返答もまだ無いので、見出しだけのカードが続く。
        items.append(.userMessage(id: "uT", text: String(repeating: "長", count: 2_000), timestamp: .distantPast))
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items, presentationContext: .gridTile))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) != nil }
        for _ in 0..<4 { try loadEarlier(host) }
        try await wait(host, stage: "見出しだけのカードを外す") { hiddenNewerCount(host) == 1 }

        client.yield(.turnInterrupted(nativeSessionId: nil))
        try await wait(host, stage: "処理の終了で末尾追従に戻る") { model.status != .running && hiddenNewerCount(host) == 0 }
        items.append(.userMessage(id: "uN", text: "やり直し", timestamp: .distantPast))
        host.rootView = ChatTranscriptView(viewModel: model, transcript: items, presentationContext: .gridTile)
        // 固定したままなら、送った入力が新しい側に 1 件外れる。
        try await Task.sleep(for: .milliseconds(200))
        try await wait(host, stage: "送った入力を描く") { hiddenNewerCount(host) == 0 }
    }


    /// 上端で引いて離して窓を固定するのと、処理の終了で見出しだけのカードが消えるのが 1 回の描画に重なっても、
    /// 末尾追従に戻る（独立レビュー 7 回目）。処理の終わった同じ会話のモデルへ、描画の前に差し替えて重ねる。
    @Test func pinnedWindowFollowsTailWhenPinAndProcessingEndShareAnUpdate() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let sessionID = SessionID()
        let client = HistoryFakeAgentClient()
        let model = ChatSessionViewModel(id: sessionID, agentRef: .builtin(.claudeCode), client: client,
                                         approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-history-test")
        client.yield(.turnStarted)
        try await wait(NSView(), stage: "実行中") { model.status == .running }
        let idleModel = ChatSessionViewModel(id: sessionID, agentRef: .builtin(.claudeCode), client: HistoryFakeAgentClient(),
                                             approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-history-test")
        var items = (0..<300).flatMap { index -> [ChatItem] in
            [.userMessage(id: "u\(index)", text: "入力", timestamp: .distantPast),
             .agentMessage(id: "a\(index)", text: "返答", timestamp: .distantPast)]
        }
        items.append(.userMessage(id: "uT", text: String(repeating: "長", count: 2_000), timestamp: .distantPast))
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items, presentationContext: .gridTile))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) != nil }
        for _ in 0..<3 {
            let before = hiddenCount(host)
            try loadEarlier(host)
            try await wait(host, stage: "段を足す") { hiddenCount(host) != before }
        }
        let wheel = try startHistoryPull(host)
        try await wait(host, stage: "ローダー") { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenNewerCount(host) == 0)
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        host.rootView = ChatTranscriptView(viewModel: idleModel, transcript: items, presentationContext: .gridTile)
        try await wait(host, stage: "描画") { element(host, "ChatTranscript.historyLoading") == nil }
        let afterRender = hiddenNewerCount(host)
        items.append(.userMessage(id: "uN", text: "やり直し", timestamp: .distantPast))
        host.rootView = ChatTranscriptView(viewModel: idleModel, transcript: items, presentationContext: .gridTile)
        try await Task.sleep(for: .milliseconds(200))
        try await wait(host, stage: "送った入力を描く afterRender=\(String(describing: afterRender))") { hiddenNewerCount(host) == 0 }
    }

    @Test(arguments: [false, true])
    func loaderPrecedesExpansionAndKeepsAnchor(grid: Bool) async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let context: TranscriptPresentationContext = grid ? .gridTile : .single
        let model = makeModel()
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: model, transcript: items, presentationContext: context))
        let window = makeWindow(host)
        defer { window.close() }
        let initial = 130 - TranscriptWindow.defaultLimit(for: context)
        try await wait(host, stage: "initial grid=\(grid)") { hiddenCount(host) == initial }
        #expect(element(host, "ChatTranscript.loadEarlier") == nil)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        host.layoutSubtreeIfNeeded()
        let previousHeight = try #require(scroll.documentView).frame.height
        let wheel = try startHistoryPull(host)
        try await wait(host, stage: "loader grid=\(grid)") { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == initial, "ローダーを表示してから履歴を追加する")
        try await Task.sleep(for: .milliseconds(400))
        #expect(hiddenCount(host) == initial, "押し続けている間は履歴を追加しない")
        #expect(element(host, "ChatTranscript.historyLoading") != nil)
        try snapshot(host, name: grid ? "history-grid-loading" : "history-single-loading")
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        // グリッドの既存描画予算は16件刻みなので、窓を50増やすと64件まで描画する。
        try await wait(host, stage: "expansion grid=\(grid)") { hiddenCount(host) == (grid ? 66 : 30) }
        try await wait(host, stage: "anchor grid=\(grid)") { scroll.contentView.bounds.minY > 0 }
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        let insertedHeight = try #require(scroll.documentView).frame.height - previousHeight
        #expect(abs(scroll.contentView.bounds.minY - insertedHeight) < 3, "追加前の先頭が上端に残る")
        try snapshot(host, name: grid ? "history-grid-expanded" : "history-single-expanded")
    }

    @Test func applicationScrollEventStartsLoader() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == 80)
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test(arguments: [(TranscriptPresentationContext.single, 118), (TranscriptPresentationContext.gridTile, 106)])
    func heavyHistoryKeepsTotalHiddenCountAcrossBudgetedExpansion(
        context: TranscriptPresentationContext, expandedHiddenCount: Int
    ) async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let heavyItems = (0..<130).map { index in
            ChatItem.userMessage(id: "heavy-\(index)", text: String(repeating: "長", count: 2_000),
                                 timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        }
        let host = NSHostingView(rootView: ChatTranscriptView(
            viewModel: makeModel(), transcript: heavyItems, presentationContext: context
        ))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 124 }

        try loadEarlier(host)

        try await wait(host) { hiddenCount(host) == expandedHiddenCount }
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func switchingSessionCancelsPendingLoad() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        host.rootView = ChatTranscriptView(viewModel: makeModel(), transcript: items)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        #expect(hiddenCount(host) == 80)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func scrollingAwayCancelsPendingLoad() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        wheel.testPhase = .ended
        NSApp.sendEvent(wheel)
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        #expect(hiddenCount(host) == 80)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        #expect(abs(scroll.contentView.bounds.minY - 200) < 3)
    }

    @Test(arguments: [false, true])
    func sessionSwitchResetsAccumulatedPull(armed: Bool) async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) {
            hiddenCount(host) == 80 && scrollViews(host).first.map(ChatAutoFollowGeometry.isAtBottom) == true
        }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = HistoryWheelEvent()
        wheel.testWindow = window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .began
        wheel.delta = 20
        NSApp.sendEvent(wheel)
        wheel.testPhase = .changed
        wheel.delta = armed ? 40 : 30
        NSApp.sendEvent(wheel)
        try await wait(host) { (element(host, "ChatTranscript.historyLoading") != nil) == armed }
        host.rootView = ChatTranscriptView(viewModel: makeModel(), transcript: items)
        try await wait(host) {
            element(host, "ChatTranscript.historyLoading") == nil && scrollViews(host).first.map(ChatAutoFollowGeometry.isAtBottom) == true
        }
        let newScroll = try #require(scrollViews(host).first)
        newScroll.contentView.scroll(to: .zero)
        wheel.testLocation = newScroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .changed
        wheel.delta = 10
        NSApp.sendEvent(wheel)
        host.layoutSubtreeIfNeeded()
        #expect(element(host, "ChatTranscript.historyLoading") == nil, "切替前の距離を持ち越さない")
        wheel.delta = 50
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        #expect(hiddenCount(host) == 80, "切替前のジェスチャーを新しいセッションへ引き継がない")
        let newWheel = try startHistoryPull(host)
        try await wait(host, stage: "切替後の新しい操作でローダーを表示") { element(host, "ChatTranscript.historyLoading") != nil }
        #expect(hiddenCount(host) == 80)
        newWheel.testPhase = .ended
        NSApp.sendEvent(newWheel)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test func scrollInputFindsViewportInFlippedContent() {
        let root = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = makeWindow(root)
        defer { window.close() }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        scroll.documentView = FlippedHistoryDocument(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        root.addSubview(scroll)
        scroll.contentView.scroll(to: .zero)
        var requests = 0
        let bridge = ChatAutoFollowScrollEventBridge(controller: ChatAutoFollowController(), onScrollPastTop: { requests += 1 })
        bridge.attach(to: scroll)
        defer { bridge.detach() }
        let event = HistoryWheelEvent()
        event.delta = 60
        event.testPhase = .began
        event.testWindow = window
        event.testLocation = scroll.convert(NSPoint(x: 150, y: 20), to: nil)
        bridge.handleScrollWheel(event)
        #expect(requests == 1)
    }

    @Test func exhaustedHistoryDoesNotLoadAgain() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: Array(items.suffix(5))))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 0 }
        try loadEarlier(host)
        try await Task.sleep(for: .milliseconds(350))
        #expect(hiddenCount(host) == 0)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func wheelWithoutPhasesLoadsOnlyAfterInputStops() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        let wheel = HistoryWheelEvent()
        wheel.testWindow = window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.delta = 30
        NSApp.sendEvent(wheel)
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(80))
            NSApp.sendEvent(wheel)
            #expect(hiddenCount(host) == 80)
        }
        try await wait(host) { hiddenCount(host) == 30 }
        #expect(element(host, "ChatTranscript.historyLoading") == nil)
    }

    @Test func cancelledPullDoesNotLoadAndAccessibilityActionStillLoads() async throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: ChatTranscriptView(viewModel: makeModel(), transcript: items))
        let window = makeWindow(host)
        defer { window.close() }
        try await wait(host) { hiddenCount(host) == 80 }
        let wheel = try startHistoryPull(host)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") != nil }
        wheel.testPhase = .cancelled
        NSApp.sendEvent(wheel)
        try await wait(host) { element(host, "ChatTranscript.historyLoading") == nil }
        #expect(hiddenCount(host) == 80)
        try loadEarlier(host)
        try await wait(host) { hiddenCount(host) == 30 }
    }

    @Test func cometHasProgressSemanticsAndCanRenderWithoutMotion() throws {
        let restoreAccessibility = enableAccessibility()
        defer { restoreAccessibility() }
        let host = NSHostingView(rootView: CometLoader())
        let window = makeWindow(host)
        defer { window.close() }
        let progress = try #require(element(host, "ChatTranscript.historyLoading"))
        #expect(attribute(progress, "accessibilityRole") as? NSAccessibility.Role == .busyIndicator)
        #expect(attribute(progress, "accessibilityLabel") as? String == "以前のメッセージを読み込み中")
        let loader = CometLoader.Ring(reduceMotion: true).frame(width: 22, height: 22)
        let renderer = ImageRenderer(content: loader)
        let image = try #require(renderer.nsImage)
        #expect(image.size == NSSize(width: 22, height: 22))
        if let output = ProcessInfo.processInfo.environment["PHLOX_COMET_SNAPSHOT_OUTPUT"] {
            let url = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for light in [false, true] {
                let sample = loader.padding(24).background(light ? Color(white: 0.94) : Color(white: 0.07))
                let sampleRenderer = ImageRenderer(content: sample)
                sampleRenderer.scale = 3
                let rendered = try #require(sampleRenderer.nsImage)
                let tiff = try #require(rendered.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("comet-\(light ? "light" : "dark").png"))
            }
        }
    }

    private var items: [ChatItem] {
        (0..<130).map { .userMessage(id: "history-\($0)", text: "メッセージ \($0)", timestamp: .distantPast) }
    }

    private func makeModel() -> ChatSessionViewModel {
        ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: DisconnectedHarnessClient(),
                            approvalBroker: ChatApprovalBroker(), workingDirectory: "/unused-history-test")
    }

    private func makeWindow(_ content: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        content.layoutSubtreeIfNeeded()
        return window
    }

    private func element(_ root: Any, _ id: String) -> AnyObject? {
        elements(root).first { attribute($0, "accessibilityIdentifier") as? String == id }
    }

    private func elements(_ root: Any) -> [AnyObject] {
        var pending: [AnyObject] = [root as AnyObject]
        var seen = Set<ObjectIdentifier>()
        var result: [AnyObject] = []
        while let object = pending.popLast() {
            guard seen.insert(ObjectIdentifier(object)).inserted else { continue }
            result.append(object)
            if let children = attribute(object, "accessibilityChildren") as? [AnyObject] { pending += children }
            if let view = object as? NSView { pending += view.subviews }
        }
        return result
    }

    private func hiddenCount(_ root: NSView) -> Int? {
        guard let history = element(root, "ChatTranscript.history"),
              let value = attribute(history, "accessibilityLabel") as? String else { return nil }
        return value.replacingOccurrences(of: ",", with: "").split(separator: " ").compactMap { Int($0) }.first
    }

    private func loadEarlier(_ root: NSView) throws {
        try performHistoryAction(root, "以前のメッセージを読み込む")
    }

    private func loadNewer(_ root: NSView) throws {
        try performHistoryAction(root, "以後のメッセージを読み込む")
    }

    private func performHistoryAction(_ root: NSView, _ name: String) throws {
        let history = try #require(element(root, "ChatTranscript.history"))
        let actions = try #require(attribute(history, "accessibilityCustomActions") as? [NSAccessibilityCustomAction])
        let action = try #require(actions.first { $0.name == name })
        try #require(action.handler?() == true)
    }

    private func hiddenNewerCount(_ root: NSView) -> Int? {
        guard let history = element(root, "ChatTranscript.history"),
              let value = attribute(history, "accessibilityLabel") as? String else { return nil }
        guard let range = value.range(of: "以後のメッセージ: ") else { return 0 }
        return value[range.upperBound...].split(separator: " ").first.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
    }

    private func startHistoryPull(_ host: NSView) throws -> HistoryWheelEvent {
        let scroll = try #require(scrollViews(host).first)
        scroll.contentView.scroll(to: .zero)
        host.layoutSubtreeIfNeeded()
        let wheel = HistoryWheelEvent()
        wheel.testWindow = scroll.window
        wheel.testLocation = scroll.convert(NSPoint(x: 150, y: 100), to: nil)
        wheel.testPhase = .began
        wheel.delta = 20
        NSApp.sendEvent(wheel)
        wheel.testPhase = .changed
        wheel.delta = 40
        NSApp.sendEvent(wheel)
        return wheel
    }

    private func wait(_ host: NSView, stage: String = "", sourceLine: Int = #line, until ready: () -> Bool) async throws {
        // 描画だけでなく、次のrun loopで取り付くAppKitのイベント購読も待つ。
        await Task.yield()
        let deadline = ContinuousClock.now + .seconds(3)
        repeat {
            host.layoutSubtreeIfNeeded()
            // 画面外のホストでは、遅延した入力監視の取り付けも明示的に完了させる。
            for resolver in elements(host).compactMap({ $0 as? ChatAutoFollowScrollObserver.ResolverView }) {
                resolver.onResolve?(resolver)
            }
            if ready() {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.main.async { continuation.resume() }
                }
                if ready() { return }
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        if let scroll = scrollViews(host).first {
            print("履歴状態: line=\(sourceLine) \(stage) clip=\(scroll.contentView.bounds) document=\(String(describing: scroll.documentView?.frame))")
        }
        for object in elements(host) {
            if let id = attribute(object, "accessibilityIdentifier") as? String, id.hasPrefix("ChatTranscript") {
                print("履歴AX: \(id) role=\(String(describing: attribute(object, "accessibilityRole"))) label=\(String(describing: attribute(object, "accessibilityLabel"))) value=\(String(describing: attribute(object, "accessibilityValue")))")
            }
        }
        try #require(ready(), "UI が期待する状態へ遷移しなかった: line=\(sourceLine) \(stage)")
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    private func attribute(_ root: AnyObject, _ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard root.responds(to: selector) else { return nil }
        return root.perform(selector)?.takeUnretainedValue()
    }

    private func enableAccessibility() -> () -> Void {
        _ = NSApplication.shared
        let key = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(key)
        NSApp.accessibilitySetValue(true, forAttribute: key)
        return { NSApp.accessibilitySetValue(previous ?? false, forAttribute: key) }
    }

    private func snapshot(_ host: NSView, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["PHLOX_COMET_SNAPSHOT_OUTPUT"] else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private final class FlippedHistoryDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class HistoryWheelEvent: NSEvent {
    var testWindow: NSWindow?
    private let eventTimestamp = ProcessInfo.processInfo.systemUptime
    var testLocation = NSPoint.zero
    var delta: CGFloat = 10
    var testPhase: NSEvent.Phase = []
    var testMomentumPhase: NSEvent.Phase = []
    override var type: NSEvent.EventType { .scrollWheel }
    override var scrollingDeltaX: CGFloat { 0 }
    override var deltaY: CGFloat { delta }
    override var deltaX: CGFloat { 0 }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var window: NSWindow? { testWindow }
    override var windowNumber: Int { testWindow?.windowNumber ?? 0 }
    override var timestamp: TimeInterval { eventTimestamp }
    override var locationInWindow: NSPoint { testLocation }
    override var scrollingDeltaY: CGFloat { delta }
    override var phase: NSEvent.Phase { testPhase }
    override var momentumPhase: NSEvent.Phase { testMomentumPhase }
}

private final class HistoryFakeAgentClient: StructuredAgentClient, @unchecked Sendable {
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

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}
