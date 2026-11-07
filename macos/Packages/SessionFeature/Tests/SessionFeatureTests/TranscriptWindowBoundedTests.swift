import Foundation
import Testing
@testable import SessionFeature

/// ADR 0228: 表示窓は上限で止まり、上限を超えて遡ると新しい側を外してずれる。
@Suite("上限付きの表示窓")
struct TranscriptWindowBoundedTests {
    private static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// 本文 100 字（重み 500）のメッセージ。上限 8 段の予算 74,400 に 148 件入る。
    private static let cappedMessageCount = TranscriptWindow.maxStages * TranscriptRenderBudget.defaultUnits / 500

    private static func messages(_ count: Int) -> [ChatItem] {
        (0..<count).map { .agentMessage(id: "m\($0)", text: String(repeating: "あ", count: 100), timestamp: timestamp) }
    }

    /// 重みの違うブロックとコマンドのまとまりが混ざった会話。
    private static func mixed(_ count: Int) -> [ChatItem] {
        (0..<count).map { index -> ChatItem in
            switch index % 7 {
            case 0: .userMessage(id: "i\(index)", text: "入力 \(index)", timestamp: timestamp)
            case 1, 2, 3: .commandExecution(id: "i\(index)", command: "ls", output: "out", timestamp: timestamp)
            case 4: .agentMessage(id: "i\(index)", text: String(repeating: "長", count: (index * 37) % 2_500), timestamp: timestamp)
            default: .reasoning(id: "i\(index)", text: "考え \(index)", timestamp: timestamp)
            }
        }
    }

    private static func renderedIDs(_ window: TranscriptWindow, _ items: [ChatItem]) -> [String] {
        window.slice(of: items).blocks.map(\.id)
    }

    @Test func 上限を超えて遡ると描画数は増えず新しい側が外れる() {
        let items = Self.messages(1_000)
        var window = TranscriptWindow()
        var counts: [Int] = []
        var previousTop = Int.max
        for _ in 0..<30 {
            let anchor = window.loadEarlier(in: items)
            let slice = window.slice(of: items)
            counts.append(slice.blocks.count)
            #expect(slice.blocks.count + slice.hiddenBlockCount + slice.hiddenNewerBlockCount == 1_000)
            #expect(anchor.map { id in slice.blocks.contains { $0.id == id } } == true, "遡る前の先頭が描画から外れた")
            let top = slice.hiddenBlockCount
            #expect(top < previousTop, "遡っても古い側が出てこない")
            previousTop = top
        }
        #expect(counts.max() == Self.cappedMessageCount, "描画数が上限の予算を超えた、または届いていない")
        #expect(window.lastItemID != nil)
        #expect(window.slice(of: items).hiddenNewerBlockCount > 0)
    }

    @Test(arguments: [TranscriptPresentationContext.single, .gridTile])
    func 軽いブロックでもずらす量は1段分で直前の端は描画に残る(context: TranscriptPresentationContext) {
        let items = (0..<2_000).map { ChatItem.userMessage(id: "u\($0)", text: "短い", timestamp: Self.timestamp) }
        let stage = TranscriptWindow.defaultLimit(for: context)
        let cap = TranscriptWindow.maxStages * stage
        var window = TranscriptWindow(context: context)
        for _ in 0..<20 {
            let before = window.slice(of: items)
            let top = window.loadEarlier(in: items)
            let after = window.slice(of: items)
            #expect(after.blocks.count <= cap)
            #expect(top.map { id in after.blocks.contains { $0.id == id } } == true, "遡る前の先頭が描画から外れた")
            #expect(before.hiddenBlockCount - after.hiddenBlockCount <= stage + TranscriptWindow.expandStep)
        }
        for _ in 0..<20 where window.lastItemID != nil {
            let before = window.slice(of: items)
            let bottom = window.loadNewer(in: items)
            let after = window.slice(of: items)
            #expect(bottom.map { id in after.blocks.contains { $0.id == id } } == true, "引く前の最後が描画から外れた")
            #expect(before.hiddenNewerBlockCount - after.hiddenNewerBlockCount <= stage)
        }
    }

    @Test func 下端で引くと新しい側へずれて末尾に戻る() {
        let items = Self.messages(1_000)
        var window = TranscriptWindow()
        for _ in 0..<20 { _ = window.loadEarlier(in: items) }
        var previousNewer = window.slice(of: items).hiddenNewerBlockCount
        var loads = 0
        while window.lastItemID != nil, loads < 200 {
            let anchor = window.loadNewer(in: items)
            let slice = window.slice(of: items)
            #expect(anchor.map { id in slice.blocks.contains { $0.id == id } } == true, "引く前の最後が描画から外れた")
            #expect(slice.hiddenNewerBlockCount < previousNewer)
            #expect(slice.blocks.count <= Self.cappedMessageCount)
            previousNewer = slice.hiddenNewerBlockCount
            loads += 1
        }
        #expect(window.lastItemID == nil, "末尾に戻らない")
        #expect(Self.renderedIDs(window, items).last == "m999")
        let anchorAtTail = window.loadNewer(in: items)
        #expect(anchorAtTail == nil, "末尾追従中は何もしない")
    }

    @Test func 新しい側を外している間に届いた項目は描画しない() {
        var items = Self.messages(1_000)
        var window = TranscriptWindow()
        for _ in 0..<10 { _ = window.loadEarlier(in: items) }
        let before = Self.renderedIDs(window, items)
        items.append(.agentMessage(id: "new", text: "新着", timestamp: Self.timestamp))
        #expect(Self.renderedIDs(window, items) == before)
        #expect(window.slice(of: items).hiddenNewerBlockCount > 0)
    }

    @Test func 終端の項目が消えたら末尾追従に戻る() throws {
        var items = Self.messages(1_000)
        var window = TranscriptWindow()
        for _ in 0..<10 { _ = window.loadEarlier(in: items) }
        let end = try #require(window.lastItemID)
        items.removeAll { $0.id == end }
        #expect(Self.renderedIDs(window, items).last == "m999")
        #expect(window.slice(of: items).hiddenNewerBlockCount == 0)
    }

    @Test(arguments: [TranscriptPresentationContext.single, .gridTile])
    func どの項目へ飛んでも飛び先が描画され上限を超えない(context: TranscriptPresentationContext) {
        let items = Self.mixed(700)
        let cap = TranscriptWindow.maxStages * TranscriptWindow.defaultLimit(for: context)
        for target in items {
            var window = TranscriptWindow(context: context)
            _ = window.reveal(itemID: target.id, in: items)
            let slice = window.slice(of: items)
            #expect(slice.blocks.contains { $0.content.contains(itemID: target.id) }, "飛び先 \(target.id) が描画されない")
            #expect(slice.blocks.count <= cap)
        }
    }

    @Test func 末尾近くへのジャンプは直後に1段分増えても飛び先が外れない() {
        var items = Self.messages(1_000)
        var window = TranscriptWindow()
        let target = items[1_000 - Self.cappedMessageCount].id
        _ = window.reveal(itemID: target, in: items)
        items += (0..<18).map { .agentMessage(id: "new\($0)", text: String(repeating: "あ", count: 100), timestamp: Self.timestamp) }
        #expect(window.slice(of: items).blocks.contains { $0.id == target })
    }

    @Test func 終端より後ろが消えたら末尾追従に戻り以後の追加を描画する() throws {
        var items = Self.messages(1_000)
        var window = TranscriptWindow()
        for _ in 0..<10 { _ = window.loadEarlier(in: items) }
        let end = try #require(window.lastItemID)
        let index = try #require(items.firstIndex { $0.id == end })
        items.removeSubrange((index + 1)...)
        window.followTailIfNothingNewer(in: items)
        #expect(window.lastItemID == nil)
        items.append(.agentMessage(id: "new", text: "x", timestamp: Self.timestamp))
        #expect(window.slice(of: items).blocks.last?.id == "new")
    }

    @Test func 新しい側が残っていれば固定を保つ() {
        let items = Self.messages(1_000)
        var window = TranscriptWindow()
        for _ in 0..<10 { _ = window.loadEarlier(in: items) }
        let before = window
        window.followTailIfNothingNewer(in: items)
        #expect(window == before)
    }

    @Test func 窓の中へのジャンプは窓を変えない() throws {
        let items = Self.mixed(700)
        var window = TranscriptWindow()
        let before = window
        let visible = try #require(window.slice(of: items).blocks.last).id
        let changedByVisible = window.reveal(itemID: visible, in: items)
        let changedByMissing = window.reveal(itemID: "missing", in: items)
        #expect(!changedByVisible)
        #expect(!changedByMissing)
        #expect(window == before)
    }

    /// 状態カードの会話（ADR 0228 §6）。最後の区間を実行中にして、固定した窓の最後の区間が実行中にならないことも見る。
    private static let cards = TranscriptBlockSource.statusCards(
        AgentStatusLiveState(isProcessing: true, activityState: .thinking, hangAssessment: nil, isAwaitingReply: false)
    )

    /// 描画が全体のブロック列の連続した一部と同じ中身で、固定した終端が入力の直前にあること。
    private static func expectWholeSegments(_ window: TranscriptWindow, _ items: [ChatItem], _ full: [ChatTranscriptBlock]) throws {
        let slice = window.slice(of: items, source: cards)
        let start = try #require(full.firstIndex { $0.id == slice.blocks.first?.id })
        let end = start + slice.blocks.count
        #expect(Array(full[start..<end]) == slice.blocks.map(\.content), "窓の中身が全体の組み立てと違う")
        #expect(slice.hiddenBlockCount == start)
        #expect(slice.hiddenNewerBlockCount == full.count - end)
        if window.lastItemID != nil {
            guard case .single(.userMessage) = full[end] else {
                Issue.record("終端が入力の直前にない: \(full[end].id)")
                return
            }
        }
    }

    @Test(arguments: [TranscriptPresentationContext.single, .gridTile])
    func 状態カードの会話では区間の途中で切らずに遡って戻れる(context: TranscriptPresentationContext) throws {
        let items = Self.mixed(3_500)
        let full = Self.cards.blocks(items)
        var window = TranscriptWindow(context: context)
        var pinned = false
        while let anchor = window.loadEarlier(in: items, source: Self.cards) {
            try Self.expectWholeSegments(window, items, full)
            #expect(window.slice(of: items, source: Self.cards).blocks.contains { $0.id == anchor }, "遡る前の先頭が描画から外れた")
            pinned = pinned || window.lastItemID != nil
        }
        #expect(window.slice(of: items, source: Self.cards).hiddenBlockCount == 0, "最古まで遡れない")
        #expect(pinned, "上限に届かず、新しい側を外す経路を通っていない")
        var loads = 0
        while window.lastItemID != nil, loads < 200 {
            let anchor = window.loadNewer(in: items, source: Self.cards)
            try Self.expectWholeSegments(window, items, full)
            #expect(anchor.map { id in window.slice(of: items, source: Self.cards).blocks.contains { $0.id == id } } == true)
            loads += 1
        }
        #expect(window.lastItemID == nil, "末尾に戻らない")
    }

    @Test(arguments: [TranscriptPresentationContext.single, .gridTile])
    func 状態カードの会話でもどの項目へ飛んでも飛び先が描画され上限を超えない(context: TranscriptPresentationContext) throws {
        let items = Self.mixed(2_100)
        let full = Self.cards.blocks(items)
        let cap = TranscriptWindow.maxStages * TranscriptWindow.defaultLimit(for: context)
        for target in items.enumerated() where target.offset % 5 == 0 {
            var window = TranscriptWindow(context: context)
            _ = window.reveal(itemID: target.element.id, in: items, source: Self.cards)
            let slice = window.slice(of: items, source: Self.cards)
            #expect(slice.blocks.contains { $0.content.contains(itemID: target.element.id) }, "飛び先 \(target.element.id) が描画されない")
            #expect(slice.blocks.count <= cap)
            try Self.expectWholeSegments(window, items, full)
        }
    }

    @Test func 最新へとセッション切替で末尾に戻る() {
        let items = Self.messages(1_000)
        var window = TranscriptWindow()
        _ = window.reveal(itemID: "m0", in: items)
        #expect(window.lastItemID != nil)
        window.followTail()
        #expect(Self.renderedIDs(window, items).last == "m999")
        _ = window.reveal(itemID: "m0", in: items)
        window.reset()
        #expect(window == TranscriptWindow())
    }
}
