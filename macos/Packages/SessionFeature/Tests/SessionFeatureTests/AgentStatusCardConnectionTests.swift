import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// エージェント状態カードの描画まわり（段 5・段 6）。組み立ては AgentStatusCardBuilderTests が持つ。
// ここは: 再描画の等価性（NFR-1・ADR 0116）、開閉と件数（FR-7・FR-8・FR-15）、Claude/Codex だけがカードを使うこと（AC-14）、
// 見出しの時計と読み上げ（NFR-3）、描画の予算、空の fileChange、グリッドの小さいタイルの見出し（FR-23）。

// MARK: - 入力の部品

private func t(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
}

private let ja = Locale(identifier: "ja")

private func user(_ id: String, at seconds: TimeInterval = 0, end: ChatTurnEnd? = nil) -> ChatItem {
    .userMessage(id: id, text: "依頼 \(id)", timestamp: t(seconds), attachments: [], turnEnd: end)
}

private func ended(_ outcome: ChatTurnEnd.Outcome, at seconds: TimeInterval) -> ChatTurnEnd {
    ChatTurnEnd(outcome: outcome, at: t(seconds))
}

private func command(_ id: String, _ text: String, at seconds: TimeInterval, done: TimeInterval? = nil) -> ChatItem {
    .commandExecution(
        id: id, command: text, output: "出力", timestamp: t(seconds), completedAt: done.map(t), intent: nil
    )
}

private func edit(_ id: String, _ path: String, at seconds: TimeInterval, done: TimeInterval? = nil) -> ChatItem {
    .fileChange(
        id: id, changes: [FilePatchChange(path: path, diff: "@@\n-a\n+b", kind: "edit")],
        timestamp: t(seconds), completedAt: done.map(t)
    )
}

private func snapshot(_ id: String, _ tasks: [(String, String, AgentTaskStatus)], at seconds: TimeInterval) -> ChatItem {
    .taskList(id: id, tasks: tasks.map { AgentTaskItem(id: $0.0, title: $0.1, status: $0.2) }, timestamp: t(seconds))
}

private func live(
    processing: Bool, activity: AgentActivityState = .thinking, hang: ChatHangAssessment? = nil
) -> AgentStatusLiveState {
    AgentStatusLiveState(isProcessing: processing, activityState: activity, hangAssessment: hang, isAwaitingReply: false)
}

private func card(_ items: [ChatItem], _ state: AgentStatusLiveState) -> AgentStatusCard? {
    let found = AgentStatusCardBuilder.build(items: items, liveState: state).compactMap {
        if case .statusCard(let card) = $0 { card } else { nil }
    }
    return found.count == 1 ? found[0] : nil
}

/// `withClosures`: 呼ぶたびに別物になるクロージャ（中断・無応答の判定）を渡す。
@MainActor
private func view(_ card: AgentStatusCard, still: Bool = false, narrow: Bool = false, withClosures: Bool = false) -> AgentStatusCardView {
    AgentStatusCardView(
        card: card, agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
        isStill: still, isNarrow: narrow,
        hangAssessment: withClosures ? { _ in nil } : nil,
        onInterrupt: withClosures ? {} : nil
    )
}

/// 実行中: タスク A（進行中。検索 1 件と実行中の編集）とタスク B（未着手）。
private func runningItems(userID: String = "u1") -> [ChatItem] {
    [
        user(userID),
        snapshot("task-list-1", [("A", "Retry-After を読む", .inProgress), ("B", "テストを足す", .pending)], at: 2),
        command("c1", "rg Retry-After", at: 3, done: 4),
        edit("e1", "/repo/client.go", at: 5),
    ]
}

private func runningCard(userID: String = "u1") -> AgentStatusCard {
    card(runningItems(userID: userID), live(processing: true))!
}

private func row(_ card: AgentStatusCard, _ index: Int) -> AgentStatusRow { card.rows[index] }

// MARK: - 再描画の等価性

@Suite("状態カード: 再描画の等価性（NFR-1・ADR 0116）")
@MainActor
struct AgentStatusCardEquatableTests {
    @Test("表示値が同じなら、毎回生成される別クロージャを渡しても equal")
    func sameValuesWithDifferentClosuresAreEqual() {
        let card = runningCard()
        let a = view(card, withClosures: true)
        let b = view(card, withClosures: true)

        #expect(a == b)
    }

    @Test("実行中でないカードは、実行中の状態（無応答の長さ・活動状態）が変わっても equal")
    func finishedCardIsEqualWhenLiveStateAdvances() {
        let items = [
            user("u1", end: ended(.completed, at: 13)),
            snapshot("task-list-1", [("A", "読む", .completed)], at: 2),
            edit("e1", "/repo/a.swift", at: 3, done: 4),
        ]
        let early = card(items, live(
            processing: false, activity: .thinking, hang: ChatHangAssessment(elapsed: 5, silence: 1, isStalled: false)
        ))!
        let late = card(items, live(
            processing: false, activity: .editing, hang: ChatHangAssessment(elapsed: 5_000, silence: 4_000, isStalled: true)
        ))!

        #expect(view(early) == view(late))
    }

    @Test("カードの中身（タスクの状態）が変われば not equal")
    func changedTaskStateIsNotEqual() {
        let before = runningCard()
        var items = runningItems()
        items.append(snapshot("task-list-2", [("A", "Retry-After を読む", .completed), ("B", "テストを足す", .inProgress)], at: 9))
        let after = card(items, live(processing: true))!

        #expect(view(before) != view(after))
    }

    @Test("点描を止める指定・狭い列の指定が変われば not equal")
    func stillAndNarrowFlagsInvalidate() {
        let card = runningCard()

        #expect(view(card) != view(card, still: true))
        #expect(view(card) != view(card, narrow: true))
    }
}

// MARK: - 開閉と件数

@Suite("状態カード: 開閉と件数（FR-7・FR-8・FR-15）")
struct AgentStatusCardDisclosureTests {
    @Test("実行中は進行中のタスクだけ自動で開き、未着手は開かない")
    func runningCardOpensOnlyTheInProgressTask() {
        let card = runningCard()
        let disclosure = AgentStatusCardDisclosure()

        #expect(disclosure.isExpanded(row(card, 0), in: card))
        #expect(!disclosure.isExpanded(row(card, 1), in: card))
        #expect(row(card, 0).isExpandable)
        #expect(!row(card, 1).isExpandable)
    }

    @Test("作業が終わったカードは、手で開かなければ全部閉じている")
    func finishedCardIsAllClosed() {
        var items = runningItems()
        items[0] = user("u1", end: ended(.completed, at: 20))
        let finished = card(items, live(processing: false))!
        let disclosure = AgentStatusCardDisclosure()

        #expect(finished.rows.allSatisfy { !disclosure.isExpanded($0, in: finished) })
    }

    @Test("見た目と反対に切り替わる（自動で開いている行を閉じ、もう一度で開く）")
    func toggleFlipsWhatIsShown() {
        let card = runningCard()
        var disclosure = AgentStatusCardDisclosure()

        disclosure.toggle(row(card, 0), in: card)
        #expect(!disclosure.isExpanded(row(card, 0), in: card))
        disclosure.toggle(row(card, 0), in: card)
        #expect(disclosure.isExpanded(row(card, 0), in: card))
    }

    @Test("手で開いたタスクは、カードが終わっても自動では閉じない")
    func manuallyOpenedTaskStaysOpenAfterTheCardFinishes() {
        let running = runningCard()
        var disclosure = AgentStatusCardDisclosure()
        // B は未着手で作業が無いので開けないが、完了したタスクは手で開ける。
        var items = runningItems()
        items.append(snapshot("task-list-2", [("A", "Retry-After を読む", .completed), ("B", "テストを足す", .inProgress)], at: 9))
        let afterA = card(items, live(processing: true))!
        #expect(!disclosure.isExpanded(row(afterA, 0), in: afterA))
        disclosure.toggle(row(afterA, 0), in: afterA)
        items[0] = user("u1", end: ended(.completed, at: 30))
        let finished = card(items, live(processing: false))!

        #expect(finished.id == running.id)
        #expect(disclosure.isExpanded(row(finished, 0), in: finished))
    }

    @Test("手で閉じた進行中のタスクは、カードが更新されても自動では開き直さない")
    func manuallyClosedTaskStaysClosedWhenTheCardUpdates() {
        let running = runningCard()
        var disclosure = AgentStatusCardDisclosure()
        disclosure.toggle(row(running, 0), in: running)
        var items = runningItems()
        items.append(command("c2", "swift test", at: 8))
        let updated = card(items, live(processing: true))!

        #expect(!disclosure.isExpanded(row(updated, 0), in: updated))
    }

    @Test("手の開閉はカード id とタスク id の組で覚える（別のカードの同じタスク id には効かない）")
    func manualStateIsKeyedByCardAndTask() {
        let first = runningCard(userID: "u1")
        let second = runningCard(userID: "u2")
        var disclosure = AgentStatusCardDisclosure()

        disclosure.toggle(row(first, 0), in: first)

        #expect(!disclosure.isExpanded(row(first, 0), in: first))
        #expect(disclosure.isExpanded(row(second, 0), in: second))
    }

    @Test("タスクが無い入力のタスク外の作業は、実行中なら開き、終わったら閉じる")
    func outsideGroupFollowsTheRunningState() {
        let items = [user("u1"), command("c1", "go mod tidy", at: 1, done: 2), command("c2", "go build", at: 3)]
        let running = card(items, live(processing: true))!
        let finished = card([user("u1", end: ended(.completed, at: 9))] + items.dropFirst(), live(processing: false))!
        let disclosure = AgentStatusCardDisclosure()

        #expect(disclosure.isExpanded(row(running, 0), in: running))
        #expect(!disclosure.isExpanded(row(finished, 0), in: finished))
    }

    /// 終わったカード。タスク A（完了）に検索 c1 と編集 e1、タスク B（完了、作業なし）。全部閉じている。
    private func finishedCardWithClosedTask() -> AgentStatusCard {
        var items = runningItems()
        items.append(snapshot("task-list-2", [("A", "Retry-After を読む", .completed), ("B", "テストを足す", .completed)], at: 9))
        items[0] = user("u1", end: ended(.completed, at: 30))
        return card(items, live(processing: false))!
    }

    @Test("作業への移動: 閉じたタスクの中の作業なら、そのタスクの行を手で開く（ほかの行は変えない）")
    func revealOpensTheClosedTaskHoldingTheItem() {
        let card = finishedCardWithClosedTask()
        var disclosure = AgentStatusCardDisclosure()
        #expect(!disclosure.isExpanded(row(card, 0), in: card))

        disclosure.reveal(itemID: "c1", in: card)

        #expect(disclosure.isExpanded(row(card, 0), in: card))
        #expect(!disclosure.isExpanded(row(card, 1), in: card))
        #expect(disclosure.isManuallyOpened(row(card, 0), in: card))
        #expect(card.entryID(containing: "c1") != nil)
        #expect(card.entryID(containing: "missing") == nil)
    }

    @Test("作業への移動: 終わったカードのタスク外の作業の行も開く。別のカードには効かない")
    func revealOpensTheOutsideGroupOnlyForThatCard() {
        let items = [user("u1", end: ended(.completed, at: 9)), command("c1", "go mod tidy", at: 1, done: 2)]
        let other = [user("u2", end: ended(.completed, at: 9)), command("c2", "go build", at: 1, done: 2)]
        let target = card(items, live(processing: false))!
        let untouched = card(other, live(processing: false))!
        var disclosure = AgentStatusCardDisclosure()

        disclosure.reveal(itemID: "c1", in: target)

        #expect(disclosure.isExpanded(row(target, 0), in: target))
        #expect(!disclosure.isExpanded(row(untouched, 0), in: untouched))
    }

    @Test("作業への移動: 「さらに表示」の外にある作業は件数を足して見える位置に入れ、窓の中なら件数を変えない")
    func revealWidensTheWindowOnlyWhenTheItemIsOutside() {
        var items: [ChatItem] = [user("u1", end: ended(.completed, at: 99))]
        for number in 0..<45 { items.append(command("c\(number)", "echo \(number)", at: Double(number), done: Double(number) + 0.5)) }
        let card = card(items, live(processing: false))!
        let outside = row(card, 0)
        var disclosure = AgentStatusCardDisclosure()

        disclosure.reveal(itemID: "c40", in: card)
        #expect(disclosure.entryLimit(outside, in: card) == AgentStatusCardDisclosure.initialEntryLimit)

        disclosure.reveal(itemID: "c0", in: card)
        let window = AgentStatusCardDisclosure.window(outside.entries, limit: disclosure.entryLimit(outside, in: card))
        #expect(window.visible.contains { $0.id == card.entryID(containing: "c0") })
        #expect(window.hidden == 0)
    }

    @Test("作業への移動の要求は、等価性に含む（変わったカードだけ作り直される）")
    @MainActor
    func revealRequestIsPartOfEquality() {
        let card = finishedCardWithClosedTask()
        let descriptor = AgentRegistry.descriptor(for: .claudeCode)
        let plain = AgentStatusCardView(card: card, agentDescriptor: descriptor)
        let asked = AgentStatusCardView(card: card, agentDescriptor: descriptor, revealRequest: AgentStatusRevealRequest(itemID: "c1", serial: 1))
        let askedAgain = AgentStatusCardView(card: card, agentDescriptor: descriptor, revealRequest: AgentStatusRevealRequest(itemID: "c1", serial: 2))

        #expect(plain != asked)
        #expect(asked != askedAgain)
        #expect(asked == AgentStatusCardView(card: card, agentDescriptor: descriptor, revealRequest: AgentStatusRevealRequest(itemID: "c1", serial: 1)))
    }

    @Test("作業が 30 件を超える行は、新しい 30 件だけ出し、古い側の件数を数える。「さらに表示」でもう 30 件")
    func windowShowsLatestThirtyThenMore() {
        var items: [ChatItem] = [user("u1")]
        for number in 0..<45 { items.append(command("c\(number)", "echo \(number)", at: Double(number), done: Double(number) + 0.5)) }
        let card = card(items, live(processing: true))!
        let outside = row(card, 0)
        var disclosure = AgentStatusCardDisclosure()

        let first = AgentStatusCardDisclosure.window(outside.entries, limit: disclosure.entryLimit(outside, in: card))
        #expect(first.visible.count == 30)
        #expect(first.visible.first?.id == "c15")
        #expect(first.visible.last?.id == "c44")
        #expect(first.hidden == 15)

        disclosure.showMore(outside, in: card)
        let second = AgentStatusCardDisclosure.window(outside.entries, limit: disclosure.entryLimit(outside, in: card))
        #expect(second.visible.count == 45)
        #expect(second.hidden == 0)
    }
}

// MARK: - Claude・Codex だけがカードを使う

@Suite("状態カード: 適用範囲（D5・AC-14）")
struct AgentStatusCardRoutingTests {
    private let items = runningItems()

    private func shapes(_ blocks: [ChatTranscriptBlock]) -> [String] {
        blocks.map { if case .statusCard = $0 { "card" } else { $0.id } }
    }

    @Test("Claude と Codex は組み立てを使い、作業はカードにまとまる")
    func claudeAndCodexUseTheBuilder() {
        for kind in [AgentKind.claudeCode, .codex] {
            let blocks = AgentStatusCardRouting.blocks(items: items, agent: kind, liveState: live(processing: true))

            #expect(shapes(blocks) == ["u1", "card"], "\(kind)")
        }
    }

    @Test("Cursor は今のブロックのまま（カードを使わない）")
    func cursorKeepsTheCurrentGrouping() {
        let blocks = AgentStatusCardRouting.blocks(items: items, agent: .cursor, liveState: live(processing: true))

        #expect(blocks == ChatTranscriptGrouping.blocks(from: items))
        #expect(shapes(blocks) == ["u1", "task-list-1", "c1", "e1"])
    }

    @Test("Claude と Codex は末尾の考え中の行を出さず、Cursor は今のまま出す")
    func thinkingIndicatorIsOnlyForCursor() {
        func shows(_ kind: AgentKind) -> Bool {
            CompactingIndicatorPresentation.shouldShowThinkingIndicator(
                showsThinkingIndicator: true, showsProcessingIndicator: true, isCompacting: false,
                usesStatusCard: AgentStatusCardRouting.usesStatusCard(kind)
            )
        }

        #expect(!shows(.claudeCode))
        #expect(!shows(.codex))
        #expect(shows(.cursor))
    }

    @Test("カードの中の item へのジャンプは、カードの id に解決する")
    func jumpTargetInsideTheCardResolvesToTheCard() {
        let blocks = AgentStatusCardRouting.blocks(items: items, agent: .claudeCode, liveState: live(processing: true))

        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "e1", inBlocks: blocks) == "status-card-u1")
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "e1", inBlocks: blocks) == 1)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "u1", inBlocks: blocks) == 0)
        #expect(ChatTranscriptGrouping.scrollTargetID(containing: "chat-bottom", inBlocks: blocks) == "chat-bottom")
    }
}

// MARK: - 見出しの時計・読み上げ

@Suite("状態カード: 見出しの時計と読み上げ（FR-4・NFR-3）")
struct AgentStatusCardHeaderClockTests {
    private func runningHeader(_ extra: [ChatItem] = []) -> AgentStatusHeader {
        card([user("u1", at: 0), edit("e1", "/repo/api.swift", at: 1)] + extra, live(processing: true))!.header
    }

    @Test("実行中は入力を送った時刻からの経過。無応答の判定が付けば無応答の長さ")
    func runningHeaderCountsFromTheInputAndSwitchesToStalled() {
        let header = runningHeader()
        let quiet = ChatHangAssessment(elapsed: 13, silence: 2, isStalled: false)
        let stalled = ChatHangAssessment(elapsed: 2_000, silence: 1_900, isStalled: true)

        #expect(header.trailing(now: t(13), assessment: quiet) == .elapsed(13))
        #expect(header.trailing(now: t(13), assessment: nil) == .elapsed(13))
        #expect(header.resolvedState(assessment: stalled) == .stalled)
        #expect(header.trailing(now: t(2_000), assessment: stalled) == .stalled(1_900))
        #expect(header.resolvedState(assessment: quiet) == .running)
    }

    @Test("終わったカードは時刻が進んでも所要時間のまま。終了（記録なし）は何も出さない")
    func finishedHeaderIsStable() {
        let done = card(
            [user("u1", at: 0, end: ended(.completed, at: 13)), edit("e1", "/repo/a.swift", at: 1, done: 2)],
            live(processing: false)
        )!.header
        let unknown = card([user("u1", at: 0), edit("e1", "/repo/a.swift", at: 1, done: 2)], live(processing: false))!.header
        let stalled = ChatHangAssessment(elapsed: 9_000, silence: 9_000, isStalled: true)

        #expect(done.trailing(now: t(5), assessment: nil) == .duration(13))
        #expect(done.trailing(now: t(99_999), assessment: stalled) == .duration(13))
        #expect(done.resolvedState(assessment: stalled) == .completed)
        #expect(unknown.trailing(now: t(5), assessment: nil) == .none)
    }

    @Test("見出しを 1 つのラベルで読む: 実行中・今の作業・経過")
    func runningSpokenLabel() {
        let header = runningHeader()

        let label = header.spokenLabel(state: .running, trailing: .elapsed(13), locale: ja)

        #expect(label == "実行中。api.swift を編集中。経過 13 秒")
    }

    @Test("完了は「完了。所要 1 分 20 秒」、無応答は「応答なし」と無応答の長さを読む")
    func finishedAndStalledSpokenLabel() {
        let done = card(
            [user("u1", at: 0, end: ended(.completed, at: 80)), edit("e1", "/repo/a.swift", at: 1, done: 2)],
            live(processing: false)
        )!.header
        let header = runningHeader()

        #expect(done.spokenLabel(state: .completed, trailing: .duration(80), locale: ja) == "完了。所要 1 分 20 秒")
        #expect(header.spokenLabel(state: .stalled, trailing: .stalled(3_725), locale: ja) == "応答なし。api.swift を編集中。無応答 1 時間 2 分")
    }

    @Test("点描の種類は今の作業から決まり、作業が無ければ状態語の元の活動状態、待機は待機")
    func orbStateFollowsTheCurrentWork() {
        let editing = runningHeader()
        let thinking = card([user("u1"), .reasoning(id: "r1", text: "考える", timestamp: t(0))], live(processing: true, activity: .searching))!.header
        let awaiting = card(
            [user("u1"), edit("e1", "/repo/a.swift", at: 1)],
            AgentStatusLiveState(isProcessing: true, activityState: .waiting, hangAssessment: nil, isAwaitingReply: true)
        )!.header

        #expect(editing.orbState == .editing)
        #expect(thinking.orbState == .searching)
        #expect(awaiting.orbState == .waiting)
    }

    @Test("タスクの行は「状態。名前。所要時間。折りたたみ済み」、作業の行は「種類。対象。時間。展開できます」と読む")
    func taskAndActionSpokenLabels() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 60)),
            snapshot("task-list-1", [("A", "backoff の純関数を追加", .inProgress)], at: 1),
            edit("e1", "/repo/client.go", at: 2, done: 2.6),
            snapshot("task-list-2", [("A", "backoff の純関数を追加", .completed)], at: 32),
        ]
        let finished = card(items, live(processing: false))!
        guard case .task(let task) = finished.rows[0], case .action(let action) = task.entries[0] else {
            Issue.record("タスクの下に作業の行が無い")
            return
        }

        #expect(finished.rows[0].spokenLabel(isExpanded: false, locale: ja) == "完了。backoff の純関数を追加。31 秒。折りたたみ済み")
        #expect(finished.rows[0].spokenLabel(isExpanded: true, locale: ja) == "完了。backoff の純関数を追加。31 秒。展開済み")
        #expect(action.spokenLabel(locale: ja) == "編集。client.go。0.6 秒。展開できます")
    }
}

// MARK: - 描画の予算

@Suite("状態カード: 描画の予算（設計 §5）")
struct AgentStatusCardRenderBudgetTests {
    @Test("重みは開いている作業の行の数に比例する（実行中は開き、終わると閉じて軽くなる）")
    func weightGrowsWithOpenEntries() {
        let running = runningCard()
        var items = runningItems()
        items[0] = user("u1", end: ended(.completed, at: 20))
        let finished = card(items, live(processing: false))!

        let base = TranscriptRenderBudget.weight(of: .statusCard(finished))
        let open = TranscriptRenderBudget.weight(of: .statusCard(running))

        #expect(running.openEntryCount == 2)
        #expect(finished.openEntryCount == 0)
        #expect(open - base == 2 * TranscriptRenderBudget.statusCardEntryUnits)
        #expect(base == TranscriptRenderBudget.otherBlockUnits + 2 * TranscriptRenderBudget.statusCardRowUnits)
    }

    @Test("開いた行の数は 30 件で頭打ち（残りは「さらに表示」）")
    func openEntryCountIsCappedAtTheInitialLimit() {
        var items: [ChatItem] = [user("u1")]
        for number in 0..<45 { items.append(command("c\(number)", "echo \(number)", at: Double(number), done: Double(number) + 0.5)) }
        let card = card(items, live(processing: true))!

        #expect(card.openEntryCount == 30)
    }
}

// MARK: - 空の fileChange・グリッドの小さいタイル

@Suite("状態カード: 空の fileChange と小さいタイルの見出し（申し送り・FR-23）")
struct AgentStatusCardEdgeTests {
    private func emptyChange(_ id: String, at seconds: TimeInterval) -> ChatItem {
        .fileChange(id: id, changes: [], timestamp: t(seconds), completedAt: t(seconds + 1))
    }

    @Test("変更が空の fileChange は作業の行にならず、「0 ファイルを編集」を出さない")
    func emptyFileChangeIsNotShownAsWork() {
        let items = [user("u1", end: ended(.completed, at: 9)), emptyChange("f0", at: 1), edit("e1", "/repo/a.swift", at: 3, done: 4)]

        let card = card(items, live(processing: false))!
        let texts = card.rows.flatMap(\.entries).compactMap { entry -> String? in
            if case .action(let action) = entry { action.text(locale: ja) } else { nil }
        }

        #expect(texts == ["a.swift を編集"])
    }

    @Test("変更が空の fileChange だけの入力は、カードを作らない")
    func onlyEmptyFileChangeMakesNoCard() {
        let items = [user("u1", end: ended(.completed, at: 9)), emptyChange("f0", at: 1)]

        #expect(card(items, live(processing: false)) == nil)
    }

    @Test("小さいタイルの見出しは、最新の入力のカードの見出しと同じ（今の作業・状態語）")
    func latestHeaderMatchesTheLastCard() {
        let items = [
            user("u0", at: 0, end: ended(.completed, at: 5)), edit("e0", "/repo/old.swift", at: 1, done: 2),
            user("u1", at: 10), edit("e1", "/repo/api.swift", at: 11),
        ]
        let state = live(processing: true)

        let header = AgentStatusCardBuilder.latestHeader(items: items, liveState: state)

        let lastCardHeader = AgentStatusCardBuilder.build(items: items, liveState: state)
            .compactMap { block -> AgentStatusHeader? in if case .statusCard(let card) = block { card.header } else { nil } }
            .last
        #expect(header == lastCardHeader)
        #expect(header?.title(locale: ja) == "api.swift を編集中")
        #expect(header?.startedAt == t(10))
    }

    @Test("最新の入力にカードが無ければ見出しは nil（文章だけの返答が届いている）")
    func latestHeaderIsNilWithoutCard() {
        let items = [user("u1", at: 0), .agentMessage(id: "a1", text: "OK", timestamp: t(1))]

        #expect(AgentStatusCardBuilder.latestHeader(items: items, liveState: live(processing: true)) == nil)
    }
}

@Suite("状態カード: 作業の完了と短時間の表示")
struct AgentStatusCardLiveWorkTests {
    @Test("タスク外の全作業が完了したら、カードの完了後も完了印で表示する")
    func completedOutsideWorkShowsDoneMark() throws {
        let items = [
            user("u1", end: ended(.completed, at: 9)),
            command("c1", "screencapture -x card.png", at: 3, done: 3.015),
        ]

        let finished = try #require(card(items, live(processing: false)))
        let outside = try #require(finished.rows.first)

        #expect(outside.markKind == .done)
    }

    @Test("0.1 秒未満で完了した作業をゼロ秒に丸めない")
    func shortCompletedWorkShowsLessThanTenth() {
        #expect(AgentStatusDurationFormat.action(0.015) == "<0.1s")
    }
}
