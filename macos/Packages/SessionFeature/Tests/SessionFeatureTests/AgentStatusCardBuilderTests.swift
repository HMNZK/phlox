import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// エージェント状態カードの組み立て（agent-status-card-design.md §4、要件 §4.1〜4.6）。
// 会話ログ（[ChatItem]）と実行中の状態から、入力 1 回ごとのカードを組み立てる純粋関数。
// 作業の振り分けは会話ログ上の位置で決める（時刻は所要時間にしか使わない）。

// MARK: - 入力の部品

private func t(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
}

private let ja = Locale(identifier: "ja")

private func user(_ id: String, at seconds: TimeInterval, end: ChatTurnEnd? = nil) -> ChatItem {
    .userMessage(id: id, text: "依頼 \(id)", timestamp: t(seconds), attachments: [], turnEnd: end)
}

private func ended(_ outcome: ChatTurnEnd.Outcome, at seconds: TimeInterval) -> ChatTurnEnd {
    ChatTurnEnd(outcome: outcome, at: t(seconds))
}

private func command(
    _ id: String, _ text: String, at seconds: TimeInterval, done: TimeInterval? = nil,
    intent: String? = nil, output: String = ""
) -> ChatItem {
    .commandExecution(
        id: id, command: text, output: output, timestamp: t(seconds),
        completedAt: done.map(t), intent: intent
    )
}

private func edit(_ id: String, _ path: String, at seconds: TimeInterval, done: TimeInterval? = nil) -> ChatItem {
    .fileChange(
        id: id, changes: [FilePatchChange(path: path, diff: "@@\n-a\n+b", kind: "edit")],
        timestamp: t(seconds), completedAt: done.map(t)
    )
}

private func write(_ id: String, _ path: String, at seconds: TimeInterval, done: TimeInterval? = nil) -> ChatItem {
    .fileChange(
        id: id, changes: [FilePatchChange(path: path, diff: "+b", kind: "write")],
        timestamp: t(seconds), completedAt: done.map(t)
    )
}

private func snapshot(_ id: String, _ tasks: [(String, String, AgentTaskStatus)], at seconds: TimeInterval) -> ChatItem {
    .taskList(id: id, tasks: tasks.map { AgentTaskItem(id: $0.0, title: $0.1, status: $0.2) }, timestamp: t(seconds))
}

private func agent(_ id: String, _ text: String = "説明します") -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: t(0))
}

private func thought(_ id: String) -> ChatItem {
    .reasoning(id: id, text: "考える", timestamp: t(0))
}

private func cost(_ id: String) -> ChatItem {
    .turnCost(id: id, costUSD: 0.04, timestamp: t(0))
}

private func live(
    processing: Bool, activity: AgentActivityState = .thinking,
    awaiting: Bool = false, hang: ChatHangAssessment? = nil
) -> AgentStatusLiveState {
    AgentStatusLiveState(isProcessing: processing, activityState: activity, hangAssessment: hang, isAwaitingReply: awaiting)
}

private let idle = live(processing: false)

// MARK: - 出力の読み取り

private func cards(_ blocks: [ChatTranscriptBlock]) -> [AgentStatusCard] {
    blocks.compactMap { if case .statusCard(let card) = $0 { card } else { nil } }
}

private func onlyCard(_ items: [ChatItem], _ state: AgentStatusLiveState = idle) -> AgentStatusCard? {
    let found = cards(AgentStatusCardBuilder.build(items: items, liveState: state))
    return found.count == 1 ? found[0] : nil
}

private func entryIDs(_ entries: [AgentStatusEntry]) -> [String] {
    entries.map(\.id)
}

private func tasks(_ card: AgentStatusCard) -> [AgentStatusTask] {
    card.rows.compactMap { if case .task(let task) = $0 { task } else { nil } }
}

private func outside(_ card: AgentStatusCard) -> [AgentStatusOutsideGroup] {
    card.rows.compactMap { if case .outside(let group) = $0 { group } else { nil } }
}

/// 行の並びを「t:<タスク id>」「o:[<中身の id>…]」で表す。
private func rowShape(_ card: AgentStatusCard) -> [String] {
    card.rows.map { row in
        switch row {
        case .task(let task): "t:\(task.id)"
        case .outside(let group): "o:\(entryIDs(group.entries).joined(separator: ","))"
        }
    }
}

private func actions(_ entries: [AgentStatusEntry]) -> [AgentStatusAction] {
    entries.compactMap { if case .action(let action) = $0 { action } else { nil } }
}

/// カード以外のブロックの id と、カードの位置（"card"）。
private func blockShape(_ blocks: [ChatTranscriptBlock]) -> [String] {
    blocks.map { if case .statusCard = $0 { "card" } else { $0.id } }
}

// MARK: - 区切り

@Suite("状態カード: 区切り（FR-1・FR-2）")
struct AgentStatusCardSegmentTests {
    @Test("作業もタスクも無く文章だけで終わった入力ではカードを作らず、今のブロックのまま")
    func textOnlyInputHasNoCard() {
        let items = [user("u1", at: 0, end: ended(.completed, at: 3)), agent("a1", "OK"), cost("c1")]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)

        #expect(blockShape(blocks) == ["u1", "a1", "c1"])
    }

    @Test("実行中で返答がまだ無い入力には、見出しだけのカードを出す")
    func runningWithoutReplyShowsHeaderOnlyCard() {
        let items = [user("u1", at: 0), thought("r1")]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: live(processing: true, activity: .thinking))

        #expect(blockShape(blocks) == ["u1", "r1", "card"])
        let card = cards(blocks)[0]
        #expect(card.header.state == .running)
        #expect(card.header.activityState == .thinking)
        #expect(card.rows.isEmpty)
    }

    @Test("実行中でも、作業の無いまま返答が届き始めたらカードを出さない（FR-2）")
    func runningTextOnlyReplyHasNoCard() {
        let items = [user("u1", at: 0), agent("a1", "OK")]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: live(processing: true))

        #expect(blockShape(blocks) == ["u1", "a1"])
    }

    @Test("入力ごとに 1 枚、カードの id は起点の入力から決まる")
    func oneCardPerInput() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 5)), command("c1", "Read /p/a.swift", at: 1, done: 2),
            user("u2", at: 10, end: ended(.completed, at: 15)), command("c2", "Read /p/b.swift", at: 11, done: 12),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)

        #expect(blockShape(blocks) == ["u1", "card", "u2", "card"])
        #expect(cards(blocks).map(\.id) == ["status-card-u1", "status-card-u2"])
    }

    @Test("最初の入力より前の item は、今のブロックのまま出す")
    func itemsBeforeFirstInputStayAsBlocks() {
        let items: [ChatItem] = [
            .error(id: "e0", message: "起動に失敗", timestamp: t(0)),
            user("u1", at: 1, end: ended(.completed, at: 5)), command("c1", "Read /p/a.swift", at: 2, done: 3),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)

        #expect(blockShape(blocks) == ["e0", "u1", "card"])
    }
}

// MARK: - 基準のスナップショット

@Suite("状態カード: 基準のスナップショット（D8）")
struct AgentStatusCardBaselineTests {
    @Test("前の入力で完了したまま触られないタスクは出ず、この入力で変わったタスクだけが出る")
    func onlyTasksChangedInThisInputAppear() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 9)),
            snapshot("s1", [("1", "設計", .completed), ("2", "実装", .inProgress)], at: 5),
            user("u2", at: 10, end: ended(.completed, at: 30)),
            snapshot("s2", [("1", "設計", .completed), ("2", "実装", .completed), ("3", "テスト", .pending)], at: 12),
        ]

        let card = cards(AgentStatusCardBuilder.build(items: items, liveState: idle))[1]

        #expect(tasks(card).map(\.id) == ["2", "3"])
    }

    @Test("前の入力で登録したタスクに、この入力で一度も触れなければ、作業だけのカードになる")
    func untouchedPreviousTasksAreNotCarriedOver() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 9)),
            snapshot("s1", [("1", "設計", .completed)], at: 5),
            user("u2", at: 10, end: ended(.completed, at: 30)),
            command("c1", "Read /p/a.swift", at: 11, done: 12),
        ]

        let card = cards(AgentStatusCardBuilder.build(items: items, liveState: idle))[1]

        #expect(rowShape(card) == ["o:c1"])
    }

    @Test("基準で進行中のタスクに属する作業でも、そのタスクがカードに出なければタスク外になる")
    func workForHiddenBaselineTaskGoesOutside() {
        let items = [
            user("u1", at: 0, end: ended(.interrupted, at: 9)),
            snapshot("s1", [("1", "設計", .inProgress)], at: 5),
            user("u2", at: 10, end: ended(.completed, at: 30)),
            command("c1", "Read /p/a.swift", at: 11, done: 12),
        ]

        let card = cards(AgentStatusCardBuilder.build(items: items, liveState: idle))[1]

        #expect(rowShape(card) == ["o:c1"])
    }

    @Test("基準で進行中だったタスクをこの入力で完了したら、その前の作業はそのタスクに属する")
    func workContinuingBaselineTaskBelongsToIt() {
        let items = [
            user("u1", at: 0, end: ended(.interrupted, at: 9)),
            snapshot("s1", [("1", "設計", .inProgress)], at: 5),
            user("u2", at: 10, end: ended(.completed, at: 30)),
            command("c1", "Read /p/a.swift", at: 11, done: 12),
            snapshot("s2", [("1", "設計", .completed)], at: 20),
        ]

        let card = cards(AgentStatusCardBuilder.build(items: items, liveState: idle))[1]

        #expect(rowShape(card) == ["t:1"])
        #expect(entryIDs(tasks(card)[0].entries) == ["c1"])
    }
}

// MARK: - 振り分け

@Suite("状態カード: 作業の振り分け（D4・位置で決める）")
struct AgentStatusCardAssignmentTests {
    @Test("進行中がちょうど 1 件の間の作業はそのタスクに属する")
    func exactlyOneInProgressOwnsWork() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "設計", .inProgress), ("2", "実装", .pending)], at: 1),
            command("c1", "Read /p/a.swift", at: 2, done: 3),
        ]

        let card = onlyCard(items)

        #expect(card.map(rowShape) == ["t:1", "t:2"])
        #expect(card.map { entryIDs(tasks($0)[0].entries) } == ["c1"])
    }

    @Test("進行中が 0 件の間の作業はタスク外になる")
    func noInProgressMeansOutside() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "設計", .pending)], at: 1),
            command("c1", "Read /p/a.swift", at: 2, done: 3),
        ]

        let card = onlyCard(items)

        #expect(card.map(rowShape) == ["o:c1", "t:1"])
    }

    @Test("進行中が 2 件の間の作業はタスク外になる（AC-5）")
    func twoInProgressMeansOutside() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "設計", .inProgress), ("2", "実装", .inProgress)], at: 1),
            command("c1", "Read /p/a.swift", at: 2, done: 3),
        ]

        let card = onlyCard(items)

        #expect(card.map(rowShape) == ["o:c1", "t:1", "t:2"])
    }

    @Test("時刻が並びと逆でも、会話ログ上の位置で直前のスナップショットから決める")
    func positionNotTimestampDecides() {
        // c1 は s1 より後ろにあるが、開始時刻は s1 より前（書き換えで開始時刻が保たれた場合）。
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "設計", .inProgress)], at: 20),
            command("c1", "Read /p/a.swift", at: 5, done: 6),
            snapshot("s2", [("1", "設計", .completed), ("2", "実装", .inProgress)], at: 21),
            command("c2", "Read /p/b.swift", at: 2, done: 3),
        ]

        let card = onlyCard(items)

        #expect(card.map { tasks($0).map { entryIDs($0.entries) } } == [["c1"], ["c2"]])
    }

    @Test("時刻を持たないサブエージェントの印も、起動した位置で進行中のタスクに属する")
    func subAgentMarkerFollowsPosition() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "調査", .inProgress)], at: 1),
            ChatItem.subAgentMarker(id: "sa1", subagentType: "Explore", description: "呼び出し元の洗い出し", status: .completed),
        ]

        let card = onlyCard(items)

        #expect(card.map { entryIDs(tasks($0)[0].entries) } == ["sa1"])
        #expect(card.map { actions(tasks($0)[0].entries).map(\.duration) } == [nil])
    }

    @Test("タスク登録前の作業はタスクの上、完了したタスクの後の作業はそのタスクの下の位置に出る（FR-9）")
    func outsideGroupsArePlacedInTimeOrder() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            command("c1", "Read /p/a.swift", at: 1, done: 2),
            snapshot("s1", [("1", "設計", .inProgress), ("2", "実装", .pending)], at: 3),
            command("c2", "Read /p/b.swift", at: 4, done: 5),
            snapshot("s2", [("1", "設計", .completed), ("2", "実装", .pending)], at: 6),
            command("c3", "Bash make", at: 7, done: 8),
        ]

        let card = onlyCard(items)

        #expect(card.map(rowShape) == ["o:c1", "t:1", "o:c3", "t:2"])
    }

    @Test("タスクの進行中に書いた文章と思考はそのタスクの中、作業の間に入る")
    func textDuringTaskStaysWithTask() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            snapshot("s1", [("1", "設計", .inProgress)], at: 1),
            command("c1", "Read /p/a.swift", at: 2, done: 3),
            agent("a1", "日付の形式も受けます"),
            thought("r1"),
            command("c2", "Read /p/b.swift", at: 4, done: 5),
            snapshot("s2", [("1", "設計", .completed)], at: 6),
        ]

        let card = onlyCard(items)

        #expect(card.map { entryIDs(tasks($0)[0].entries) } == ["c1", "a1", "r1", "c2"])
    }
}

// MARK: - カードの上・中・下

@Suite("状態カード: カードの上・中・下（FR-16〜FR-18）")
struct AgentStatusCardPlacementTests {
    @Test("最初の作業より前の文章と思考は上、最後の返答と使用量は終わったら下に出る")
    func finishedCardSplitsAboveInsideBelow() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 13)),
            agent("a0", "確かめてから直します"),
            thought("r0"),
            command("c1", "Read /p/a.swift", at: 1, done: 2),
            agent("a1", "直しました"),
            cost("k1"),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)

        #expect(blockShape(blocks) == ["u1", "a0", "r0", "card", "a1", "k1"])
        #expect(cards(blocks).map(rowShape) == [["o:c1"]])
    }

    @Test("実行中は最後の返答もカードの中に出る")
    func runningCardKeepsLatestReplyInside() {
        let items = [
            user("u1", at: 0),
            command("c1", "Read /p/a.swift", at: 1, done: 2),
            agent("a1", "直しています"),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: live(processing: true))

        #expect(blockShape(blocks) == ["u1", "card"])
        #expect(cards(blocks).map(rowShape) == [["o:c1,a1"]])
    }

    @Test("最新の入力が終わっていても、バックグラウンドが動いている間は返答をカードの中に残す")
    func processingAfterTurnEndKeepsReplyInside() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 13)),
            command("c1", "Read /p/a.swift", at: 1, done: 2),
            agent("a1", "直しました"),
            cost("k1"),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: live(processing: true))

        #expect(blockShape(blocks) == ["u1", "card"])
    }

    @Test("最後の item が返答でなければ、使用量だけを下に出し、作業はカードの中に残す")
    func lastItemNotReplyKeepsItInside() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 13)),
            command("c1", "Read /p/a.swift", at: 1, done: 2),
            cost("k1"),
        ]

        let blocks = AgentStatusCardBuilder.build(items: items, liveState: idle)

        #expect(blockShape(blocks) == ["u1", "card", "k1"])
        #expect(cards(blocks).map(rowShape) == [["o:c1"]])
    }
}

// MARK: - 所要時間

@Suite("状態カード: 所要時間（FR-6・D13）")
struct AgentStatusCardDurationTests {
    @Test("タスクの所要時間は、最初に進行中として現れたスナップショットから最初に完了として現れたスナップショットまで")
    func taskDurationSpansFirstInProgressToFirstCompleted() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 100)),
            snapshot("s1", [("1", "設計", .pending)], at: 5),
            snapshot("s2", [("1", "設計", .inProgress)], at: 10),
            command("c1", "Read /p/a.swift", at: 12, done: 13),
            snapshot("s3", [("1", "設計", .completed)], at: 41),
        ]

        let task = onlyCard(items).map(tasks)?.first

        #expect(task?.state == .completed)
        #expect(task?.startedAt == t(10))
        #expect(task?.endedAt == t(41))
    }

    @Test("実行中の進行中タスクは終わりの時刻を持たない（表示側が今の時刻で数える）")
    func runningTaskHasNoEnd() {
        let items = [
            user("u1", at: 0),
            snapshot("s1", [("1", "設計", .inProgress)], at: 10),
        ]

        let task = onlyCard(items, live(processing: true)).map(tasks)?.first

        #expect(task?.state == .inProgress)
        #expect(task?.startedAt == t(10))
        #expect(task?.endedAt == nil)
    }

    @Test("中断したカードでは、進行中だったタスクが中断の印になり、所要時間は中断した時刻まで（AC-7）")
    func interruptedCardMarksInProgressTask() {
        let items = [
            user("u1", at: 0, end: ended(.interrupted, at: 42)),
            snapshot("s1", [("1", "設計", .completed), ("2", "実装", .inProgress), ("3", "検証", .pending)], at: 18),
        ]

        let card = onlyCard(items)

        #expect(card.map { tasks($0).map(\.state) } == [.completed, .interrupted, .pending])
        #expect(card.map { tasks($0)[1].endedAt } == t(42))
    }

    @Test("作業の所要時間は、開始から結果が届くまで")
    func actionDurationIsStartToCompletion() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 30)),
            command("c1", "Bash go test ./...", at: 2, done: 6.5),
        ]

        let action = onlyCard(items).flatMap { actions(outside($0).flatMap(\.entries)).first }

        #expect(action?.duration == 4.5)
        #expect(action?.isRunning == false)
    }

    @Test("結果がまだの作業は、実行中のカードでは進行中で所要時間を持たない")
    func runningActionHasNoDuration() {
        let items = [
            user("u1", at: 0),
            edit("e1", "/p/api.swift", at: 2),
        ]

        let action = onlyCard(items, live(processing: true)).flatMap { actions(outside($0).flatMap(\.entries)).first }

        #expect(action?.isRunning == true)
        #expect(action?.duration == nil)
    }

    @Test("見出しの所要時間は入力を送った時刻から終わった時刻まで")
    func headerSpansInputToTurnEnd() {
        let items = [
            user("u1", at: 7, end: ended(.completed, at: 20)),
            command("c1", "Read /p/a.swift", at: 8, done: 9),
        ]

        let header = onlyCard(items)?.header

        #expect(header?.startedAt == t(7))
        #expect(header?.endedAt == t(20))
    }

    @Test("時間の書き方は m:ss、1 時間以上は h:mm:ss、60 秒未満も 0:09（FR-4）")
    func clockFormat() {
        #expect(AgentStatusDurationFormat.clock(9) == "0:09")
        #expect(AgentStatusDurationFormat.clock(73.9) == "1:13")
        #expect(AgentStatusDurationFormat.clock(3_599) == "59:59")
        #expect(AgentStatusDurationFormat.clock(3_600) == "1:00:00")
        #expect(AgentStatusDurationFormat.clock(3_725) == "1:02:05")
    }

    @Test("作業の時間は 10 秒未満を小数 1 桁、60 秒未満を整数秒、それ以上を m:ss で書く")
    func actionSecondsFormat() {
        #expect(AgentStatusDurationFormat.action(0.94) == "0.9s")
        #expect(AgentStatusDurationFormat.action(4.8) == "4.8s")
        #expect(AgentStatusDurationFormat.action(14.2) == "14s")
        #expect(AgentStatusDurationFormat.action(75) == "1:15")
    }
}

// MARK: - 古い会話

@Suite("状態カード: この機能より前の会話（FR-22・AC-11）")
struct AgentStatusCardLegacyTests {
    @Test("固定 id の 1 枚に進行中がちょうど 1 件あっても、作業はタスク外にまとめる")
    func legacySnapshotNeverOwnsWork() {
        let items = [
            user("u1", at: 0),
            snapshot("task-list", [("1", "設計", .completed), ("2", "実装", .inProgress)], at: 1),
            command("c1", "Read /p/a.swift", at: 2),
            edit("e1", "/p/a.swift", at: 3),
        ]

        let card = onlyCard(items)

        #expect(card.map(rowShape) == ["t:1", "o:c1,e1", "t:2"])
    }

    @Test("固定 id の 1 枚は最後の状態だけを出し、タスクにも作業にも所要時間を付けない")
    func legacyCardHasNoDurations() {
        let items = [
            user("u1", at: 0),
            snapshot("task-list", [("1", "設計", .completed), ("2", "実装", .inProgress)], at: 1),
            command("c1", "Read /p/a.swift", at: 2),
        ]

        let card = onlyCard(items)

        #expect(card.map { tasks($0).map(\.startedAt) } == [nil, nil])
        #expect(card.map { tasks($0).map(\.endedAt) } == [nil, nil])
        #expect(card.map { actions(outside($0).flatMap(\.entries)).map(\.duration) } == [nil])
    }

    @Test("終わり方の記録が無い作業は、カードが実行中でなければ「〜中」にしない")
    func legacyActionsAreNotRunning() {
        let items = [
            user("u1", at: 0),
            edit("e1", "/p/api.swift", at: 3),
        ]

        let card = onlyCard(items)

        #expect(card?.header.state == .ended)
        #expect(card.map { actions(outside($0).flatMap(\.entries)).map(\.isRunning) } == [false])
    }
}

// MARK: - 見出し

@Suite("状態カード: 見出しの状態（要件 §4.2・FR-5）")
struct AgentStatusCardHeaderTests {
    private func header(_ end: ChatTurnEnd?, _ state: AgentStatusLiveState = idle) -> AgentStatusHeader? {
        onlyCard([user("u1", at: 0, end: end), command("c1", "Read /p/a.swift", at: 1, done: 2)], state)?.header
    }

    @Test("終わり方の記録から完了・中断・エラー・次の入力へ続くを決める")
    func headerFollowsTurnEnd() {
        #expect(header(ended(.completed, at: 13))?.state == .completed)
        #expect(header(ended(.interrupted, at: 13))?.state == .interrupted)
        #expect(header(ended(.error, at: 13))?.state == .error)
        #expect(header(ended(.superseded, at: 13))?.state == .superseded)
    }

    @Test("終わり方の記録が無く実行中でもなければ「終了」で、所要時間を持たない")
    func headerWithoutTurnEndIsEnded() {
        let found = header(nil)

        #expect(found?.state == .ended)
        #expect(found?.endedAt == nil)
    }

    @Test("最新のカードでは、終わり方の記録より実行中を優先する（バックグラウンドが動いている間）")
    func latestCardPrefersProcessing() {
        let found = header(ended(.completed, at: 13), live(processing: true))

        #expect(found?.state == .running)
        #expect(found?.endedAt == nil)
    }

    @Test("最新でないカードは、実行中でも終わり方の記録に従う")
    func olderCardIgnoresProcessing() {
        let items = [
            user("u1", at: 0), command("c1", "Read /p/a.swift", at: 1, done: 2),
            user("u2", at: 10), command("c2", "Read /p/b.swift", at: 11),
        ]

        let found = cards(AgentStatusCardBuilder.build(items: items, liveState: live(processing: true)))

        #expect(found.map(\.header.state) == [.ended, .running])
    }

    @Test("最新の入力にカードが出なくても、前のカードを実行中にしない")
    func latestInputWithoutCardDoesNotRevivePreviousCard() {
        let items = [
            user("u1", at: 0, end: ended(.completed, at: 5)), command("c1", "Read /p/a.swift", at: 1, done: 2),
            user("u2", at: 10), agent("a2", "OK"),
        ]

        let found = cards(AgentStatusCardBuilder.build(items: items, liveState: live(processing: true)))

        #expect(found.map(\.header.state) == [.completed])
    }

    @Test("実行中の見出しは、区間の最後の作業を今の作業にする")
    func runningHeaderShowsLastAction() {
        let items = [
            user("u1", at: 0),
            command("c1", "Read /p/client.go", at: 1, done: 2),
            edit("e1", "/p/api.swift", at: 3),
        ]

        let found = onlyCard(items, live(processing: true))?.header

        #expect(found?.state == .running)
        #expect(found?.title(locale: ja) == "api.swift を編集中")
    }

    @Test("承認・質問待ちの間は「待機中…」")
    func awaitingReplyHeader() {
        let found = header(nil, live(processing: true, awaiting: true))

        #expect(found?.state == .awaitingReply)
        #expect(found?.title(locale: ja) == "待機中…")
    }

    @Test("無応答と判定されたら、今の作業と無応答の長さを持つ")
    func stalledHeader() {
        let hang = ChatHangAssessment(elapsed: 2_000, silence: 1_850, isStalled: true)

        let found = header(nil, live(processing: true, hang: hang))

        #expect(found?.state == .stalled)
        #expect(found?.silence == 1_850)
        #expect(found?.title(locale: ja) == "a.swift を読み込み中")
    }

    @Test("見出しの文言（日本語）")
    func headerTitles() {
        #expect(header(ended(.completed, at: 13))?.title(locale: ja) == "完了")
        #expect(header(ended(.interrupted, at: 13))?.title(locale: ja) == "中断")
        #expect(header(ended(.error, at: 13))?.title(locale: ja) == "エラー")
        #expect(header(ended(.superseded, at: 13))?.title(locale: ja) == "次の入力へ続く")
        #expect(header(nil)?.title(locale: ja) == "終了")
    }

    @Test("作業の前の実行中の見出しは、今の活動状態の語")
    func runningBeforeWorkUsesActivityWord() {
        let found = onlyCard([user("u1", at: 0)], live(processing: true, activity: .searching))?.header

        #expect(found?.title(locale: ja) == "検索中…")
    }
}

// MARK: - superseded（実行中の再送信）

@Suite("状態カード: 実行中に次の入力を送ったとき（FR-3）")
struct AgentStatusCardSupersededTests {
    /// A を実行中に B を送り、A の遅れた完了は吸収された（A2）。A の使用量は B の区間に追記されている。
    private let items = [
        user("uA", at: 0, end: ended(.superseded, at: 36)),
        command("cA", "Read /p/a.swift", at: 1, done: 2),
        user("uB", at: 36),
        cost("kA"),
        command("cB", "Read /p/b.swift", at: 40, done: 41),
    ]

    @Test("前のカードは実行中でも「次の入力へ続く」、所要時間は次の入力を送った時刻まで")
    func previousCardIsSuperseded() {
        let found = cards(AgentStatusCardBuilder.build(items: items, liveState: live(processing: true)))

        #expect(found.map(\.header.state) == [.superseded, .running])
        #expect(found[0].header.endedAt == t(36))
        #expect(found[1].header.startedAt == t(36))
    }

    @Test("次の入力の終わりが吸収されて記録が無ければ、実行が止んだ後は「終了」になる")
    func absorbedEndLeavesNextCardEnded() {
        let found = cards(AgentStatusCardBuilder.build(items: items, liveState: idle))

        #expect(found.map(\.header.state) == [.superseded, .ended])
    }

    @Test("前の入力の使用量が次の区間の先頭にあっても、次のカードの下には出さない")
    func previousCostDoesNotBecomeNextBottom() {
        var completed = items
        completed[2] = user("uB", at: 36, end: ended(.completed, at: 50))
        completed += [agent("aB", "直しました"), cost("kB")]

        let blocks = AgentStatusCardBuilder.build(items: completed, liveState: idle)

        #expect(blockShape(blocks) == ["uA", "card", "uB", "card", "aB", "kB"])
    }
}

// MARK: - 作業の行の文言とまとめ

@Suite("状態カード: 作業の行の文言とまとめ（FR-10〜FR-12）")
struct AgentStatusCardActionTextTests {
    private func rows(_ work: [ChatItem], _ state: AgentStatusLiveState = idle) -> [AgentStatusAction] {
        let end: ChatTurnEnd? = state.isProcessing ? nil : ended(.completed, at: 900)
        return onlyCard([user("u1", at: 0, end: end)] + work, state).map { actions(outside($0).flatMap(\.entries)) } ?? []
    }

    private func texts(_ work: [ChatItem], _ state: AgentStatusLiveState = idle) -> [String] {
        rows(work, state).map { $0.text(locale: ja) }
    }

    @Test("読み込みはファイル名、進行中は「〜中」")
    func readUsesFileName() {
        #expect(texts([command("c1", "Read /p/src/client.go", at: 1, done: 2)]) == ["client.go を読み込み"])
        #expect(texts([command("c1", "Read /p/src/client.go", at: 1)], live(processing: true)) == ["client.go を読み込み中"])
    }

    @Test("続けて読んだファイルは 1 行にまとめる")
    func consecutiveReadsMerge() {
        let work = [command("c1", "Read /p/client.go", at: 1, done: 1.25), command("c2", "Read /p/retry.go", at: 1.5, done: 1.75)]

        let merged = rows(work)

        #expect(merged.map { $0.text(locale: ja) } == ["client.go ほか 1 ファイルを読み込み"])
        #expect(merged.map(\.duration) == [0.75])
        #expect(merged.map { $0.items.map(\.id) } == [["c1", "c2"]])
    }

    @Test("検索は対象と、結果の行数から「N 件」まで出す")
    func searchShowsHitCount() {
        let found = command("c1", "Grep Retry-After", at: 1, done: 1.4, output: "a.go:1\nb.go:2\n\nc.go:3\nd.go:4\n")

        #expect(texts([found]) == ["「Retry-After」を検索 · 4 件"])
        #expect(texts([command("c1", "Grep Retry-After", at: 1)], live(processing: true)) == ["「Retry-After」を検索中"])
    }

    @Test("続けて検索したら回数と件数の合計にまとめる")
    func consecutiveSearchesMerge() {
        let work = [
            command("c1", "Grep foo", at: 1, done: 2, output: "a\nb"),
            command("c2", "Glob **/*.swift", at: 2, done: 3, output: "x.swift\ny.swift\nz.swift"),
        ]

        #expect(texts(work) == ["2 回検索 · 5 件"])
    }

    @Test("続けて編集したファイルは、異なるファイルの数でまとめる")
    func consecutiveEditsMergeByDistinctFiles() {
        let work = [
            edit("e1", "/p/a.swift", at: 1, done: 1.2), edit("e2", "/p/b.swift", at: 1.3, done: 1.5),
            edit("e3", "/p/a.swift", at: 1.6, done: 1.8), edit("e4", "/p/c.swift", at: 1.9, done: 2.1),
            edit("e5", "/p/d.swift", at: 2.2, done: 2.4), edit("e6", "/p/e.swift", at: 2.5, done: 2.9),
        ]

        #expect(texts(work) == ["5 ファイルを編集"])
    }

    @Test("同じファイルを続けて編集したら、ファイル名の 1 行")
    func repeatedEditOfOneFile() {
        let work = [edit("e1", "/p/a.swift", at: 1, done: 2), edit("e2", "/p/a.swift", at: 3, done: 4)]

        #expect(texts(work) == ["a.swift を編集"])
    }

    @Test("書き込みはまとめない")
    func writesDoNotMerge() {
        let work = [write("w1", "/p/a.md", at: 1, done: 2), write("w2", "/p/b.md", at: 3, done: 4)]

        #expect(texts(work) == ["a.md に書き込み", "b.md に書き込み"])
    }

    @Test("コマンドの実行はまとめず、説明があれば説明、無ければコマンドを出す")
    func commandsUseIntentAndNeverMerge() {
        let work = [
            command("c1", "go test ./internal/... -run TestRetry", at: 1, done: 5.8, intent: "再試行のテストを実行"),
            command("c2", "go test ./... -count=1", at: 6, done: 12.2),
        ]

        #expect(texts(work) == ["再試行のテストを実行", "go test ./... -count=1"])
    }

    @Test("実行中のコマンドは、説明なら「〜中」、コマンドなら「〜を実行中」")
    func runningCommandWording() {
        let state = live(processing: true)

        #expect(texts([command("c1", "go build ./...", at: 1, intent: "ビルドが通るか確認")], state) == ["ビルドが通るか確認中"])
        #expect(texts([command("c1", "go build ./...", at: 1)], state) == ["go build ./... を実行中"])
    }

    @Test("間に文章が入ったら、同じ種類でもまとめない")
    func textBreaksMerge() {
        let work = [
            command("c1", "Read /p/a.swift", at: 1, done: 2), agent("a1", "次を見ます"),
            command("c2", "Read /p/b.swift", at: 3, done: 4),
        ]

        #expect(texts(work) == ["a.swift を読み込み", "b.swift を読み込み"])
    }

    @Test("その他のツールはツール名で出す")
    func otherToolUsesName() {
        #expect(texts([command("c1", "Skill {\"skill\":\"x\"}", at: 1, done: 2)]) == ["Skill を実行"])
    }

    @Test("サブエージェントは説明・種類・状態を持つ 1 行")
    func subAgentRow() {
        let marker = ChatItem.subAgentMarker(id: "sa1", subagentType: "Explore", description: "呼び出し元の洗い出し", status: .completed)

        let row = rows([marker]).first

        #expect(row?.label == .subAgent(description: "呼び出し元の洗い出し", type: "Explore", status: .completed))
        #expect(row?.text(locale: ja) == "呼び出し元の洗い出し")
    }

    @Test("英語の文言は xcstrings から引ける")
    func englishWordingComesFromCatalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("status-card-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try catalogBundle(at: root)
        let en = Locale(identifier: "en")
        let interrupted = AgentStatusHeader(
            state: .interrupted, current: nil, activityState: nil, startedAt: t(0), endedAt: t(1), silence: nil
        )

        #expect(AgentStatusAction.Label.read(file: "client.go", more: 1).text(running: false, locale: en, bundle: bundle)
            == "Read client.go and 1 more file(s)")
        #expect(AgentStatusAction.Label.editFiles(count: 5).text(running: false, locale: en, bundle: bundle)
            == "Edited 5 files")
        #expect(AgentStatusAction.Label.search(query: "Retry-After", hits: 4).text(running: false, locale: en, bundle: bundle)
            == "Searched for “Retry-After” · 4 results")
        #expect(interrupted.title(locale: en, bundle: bundle) == "Interrupted")
    }

    /// App/Localizable.xcstrings の英語を、一時的な en.lproj に書き出して読む（ProjectTabsPresentationTests と同じ方法）。
    private func catalogBundle(at root: URL) throws -> Bundle {
        let english = root.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        let macos = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: macos.appendingPathComponent("App/Localizable.xcstrings"))
        ) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        var translations: [String: String] = [:]
        for (key, value) in strings {
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let en = localizations["en"] as? [String: Any],
                  let unit = en["stringUnit"] as? [String: Any],
                  let text = unit["value"] as? String else { continue }
            translations[key] = text
        }
        try PropertyListSerialization.data(fromPropertyList: translations, format: .xml, options: 0)
            .write(to: english.appendingPathComponent("Localizable.strings"))
        return try #require(Bundle(url: root))
    }
}
