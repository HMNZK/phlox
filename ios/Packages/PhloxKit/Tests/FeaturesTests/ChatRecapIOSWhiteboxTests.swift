import Foundation
import Testing
import PhloxCore
@testable import Features

/// task-4 白箱: ChatRecapIOS.derive の gate / scope / mapping と thinkingStartedAt 追従を網羅。
@Suite("ChatRecapIOS 白箱")
struct ChatRecapIOSWhiteboxTests {
    let threshold: TimeInterval = ThinkingRecap.defaultThreshold

    func user(_ id: String = "u") -> ChatMessage { .user(id: id, text: "hi") }
    func reasoning(_ text: String, _ id: String = "r") -> ChatMessage {
        .reasoning(id: id, text: text)
    }
    func command(_ cmd: String?, _ id: String = "c") -> ChatMessage {
        .command(id: id, command: cmd, output: "")
    }
    func file(_ path: String, _ id: String = "f") -> ChatMessage {
        .fileChange(id: id, changes: [ChatFileChange(path: path, diff: "")])
    }
    func emptyFile(_ id: String = "f0") -> ChatMessage {
        .fileChange(id: id, changes: [])
    }

    // MARK: - gate

    @Test("starting / completed / error / idle では nil")
    func gateNonRunningStatuses() {
        let msgs = [user(), reasoning("## X")]
        #expect(ChatRecapIOS.derive(messages: msgs, status: .starting, elapsed: 10, threshold: threshold) == nil)
        #expect(ChatRecapIOS.derive(messages: msgs, status: .completed(exitCode: 0), elapsed: 10, threshold: threshold) == nil)
        #expect(ChatRecapIOS.derive(messages: msgs, status: .error(message: "e"), elapsed: 10, threshold: threshold) == nil)
        #expect(ChatRecapIOS.derive(messages: msgs, status: .idle, elapsed: 10, threshold: threshold) == nil)
    }

    @Test("承認・質問待ちでも Mac と同じ recap を使う")
    func waitingStatusesUseActivitySummary() {
        let msgs = [user(), reasoning("## 設計"), command("swift build")]
        #expect(ChatRecapIOS.derive(
            messages: msgs,
            status: .awaitingApproval(prompt: "続行?"),
            elapsed: 10,
            threshold: threshold
        ) == "swift build を実行中")
        #expect(ChatRecapIOS.derive(
            messages: msgs,
            status: .awaitingUserQuestion,
            elapsed: 10,
            threshold: threshold
        ) == "swift build を実行中")
    }

    @Test("閾値ちょうどは通す（elapsed < threshold のみ gate）")
    func gateAtThreshold() {
        let r = ChatRecapIOS.derive(
            messages: [user(), reasoning("末尾")],
            status: .running,
            elapsed: threshold,
            threshold: threshold
        )
        #expect(r == "末尾")
    }

    @Test("閾値未満は nil")
    func gateJustBelowThreshold() {
        #expect(
            ChatRecapIOS.derive(
                messages: [user(), reasoning("末尾")],
                status: .running,
                elapsed: threshold - 0.001,
                threshold: threshold
            ) == nil
        )
    }

    // MARK: - scope

    @Test("user が無いときは messages 全体が対象")
    func scopeWholeWhenNoUser() {
        let msgs = [command("swift build"), reasoning("## 設計")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "swift build を実行中"
        )
    }

    @Test("複数 user があるとき最後の直後だけが対象")
    func scopeAfterLastOfMultipleUsers() {
        let msgs = [
            user("u1"), command("old"),
            user("u2"), command("ls"),
        ]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "ls を読み込み中"
        )
    }

    // MARK: - mapping

    @Test("reasoning は最新で上書き")
    func reasoningLatestWins() {
        let msgs = [user(), reasoning("## 古い", "r1"), reasoning("## 新しい", "r2")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "新しい"
        )
    }

    @Test("activities は古い→新しい順で last が優先")
    func activitiesOldestToNewest() {
        let msgs = [user(), file("A.swift"), command("rg foo"), command("swift test")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "swift test を実行中"
        )
    }

    @Test("fileChange で changes が空なら活動に足さない")
    func emptyFileChangeIgnored() {
        let msgs = [user(), emptyFile(), reasoning("## 見出しだけ")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "見出しだけ"
        )
    }

    @Test("command nil は RecapActivity.fromCommand に委譲")
    func nilCommandDelegates() {
        let msgs = [user(), command(nil)]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "コマンド を実行中"
        )
    }

    @Test("agent / error / subAgent 等は無視")
    func otherCasesIgnored() {
        let msgs: [ChatMessage] = [
            user(),
            .agent(id: "a", text: "hi"),
            .error(id: "e", message: "boom"),
            .subAgent(id: "s", text: "spawn"),
            reasoning("## 残る"),
        ]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "残る"
        )
    }

    @Test("活動があれば reasoning より優先")
    func activityBeatsReasoning() {
        let msgs = [user(), reasoning("## 無視される"), command("cat a")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "cat a を読み込み中"
        )
    }

    @Test("Mac と同じく最後の fileChange の basename を要約する")
    func latestChangedPathUsesBasename() {
        let msgs: [ChatMessage] = [
            user(),
            .fileChange(id: "f", changes: [
                ChatFileChange(path: "Sources/Old.swift", diff: ""),
                ChatFileChange(path: "Packages/Current.swift", diff: ""),
            ]),
        ]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "Current.swift を編集中"
        )
    }

    @Test("後から続く reasoning があっても直近の活動を優先する")
    func activityAfterReasoningWins() {
        let msgs = [user(), command("swift build"), reasoning("## 後続の考え")]
        #expect(
            ChatRecapIOS.derive(messages: msgs, status: .running, elapsed: 10, threshold: threshold)
                == "swift build を実行中"
        )
    }

    @Test("経過時間は60秒未満を秒、以降をゼロ埋めの分秒で表す")
    func elapsedLabelMatchesMac() {
        #expect(ChatRecapIOS.elapsedLabel(38) == "38 秒")
        #expect(ChatRecapIOS.elapsedLabel(192) == "3:12")
    }

    @Test("カスタム threshold を渡せる")
    func customThreshold() {
        #expect(
            ChatRecapIOS.derive(
                messages: [user(), command("x")],
                status: .running,
                elapsed: 3,
                threshold: 5
            ) == nil
        )
        #expect(
            ChatRecapIOS.derive(
                messages: [user(), command("x")],
                status: .running,
                elapsed: 3,
                threshold: 2
            ) == "x を実行中"
        )
    }
}

/// thinkingStartedAt の running 遷移追従（ポーリングで暴れないこと）。
@Suite("SessionDetailViewModel thinkingStartedAt 白箱")
@MainActor
struct SessionDetailThinkingStartedAtWhiteboxTests {
    private func session(_ status: SessionStatus) -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: status,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("init 時に running なら thinkingStartedAt が非 nil")
    func initRunningSetsStartedAt() {
        let vm = SessionDetailViewModel(session: session(.running), api: MockAPI())
        #expect(vm.thinkingStartedAt != nil)
    }

    @Test("init 時に idle なら thinkingStartedAt は nil")
    func initIdleLeavesNil() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        #expect(vm.thinkingStartedAt == nil)
    }

    @Test("running → idle で thinkingStartedAt が nil にリセット")
    func leavingRunningClears() async {
        let mock = MockAPI()
        await mock.setSessions([session(.running)])
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        #expect(vm.thinkingStartedAt != nil)

        await mock.setSessions([session(.idle)])
        await vm.refresh()
        #expect(vm.currentStatus == .idle)
        #expect(vm.thinkingStartedAt == nil)
    }

    @Test("awaitingApproval / awaitingUserQuestion でも statusEnteredAt から recap を計る")
    func waitingStatusesTrackTheirEnteredAt() async {
        let enteredAt = Date(timeIntervalSince1970: 1_900_000_000)
        let messages: [ChatMessage] = [
            .user(id: "u", text: "実行して"),
            .command(id: "c", command: "swift build", output: ""),
        ]
        for status in [SessionStatus.awaitingApproval(prompt: "続行?"), .awaitingUserQuestion] {
            let waitingSession = Session(
                id: "s1", name: "Rose", agent: .claudeCode,
                status: status, subtitle: "", statusEnteredAt: enteredAt,
                updatedAt: enteredAt
            )
            let api = MockAPI(messagesOutcome: .success(messages))
            let vm = SessionDetailViewModel(session: waitingSession, api: api)
            await vm.load()

            #expect(vm.thinkingStartedAt == enteredAt)
            #expect(vm.recap(now: enteredAt.addingTimeInterval(10)) == "swift build を実行中 · 10 秒")
        }
    }

    @Test("idle → running で thinkingStartedAt が記録される")
    func enteringRunningRecords() async {
        let mock = MockAPI()
        await mock.setSessions([session(.idle)])
        let vm = SessionDetailViewModel(session: session(.idle), api: mock)
        #expect(vm.thinkingStartedAt == nil)

        await mock.setSessions([session(.running)])
        await vm.refresh()
        #expect(vm.currentStatus == .running)
        #expect(vm.thinkingStartedAt != nil)
    }

    @Test("実行中から承認待ちへ移ると statusEnteredAt を使い、同じ状態の更新では保つ")
    func enteringWaitingUsesStatusEnteredAtWithoutThrashing() async {
        let enteredAt = Date(timeIntervalSince1970: 1_900_000_000)
        let running = Session(
            id: "s1", name: "Rose", agent: .claudeCode,
            status: .running, subtitle: "", statusEnteredAt: enteredAt.addingTimeInterval(-20),
            updatedAt: enteredAt
        )
        let waiting = Session(
            id: "s1", name: "Rose", agent: .claudeCode,
            status: .awaitingApproval(prompt: "approve"), subtitle: "", statusEnteredAt: enteredAt,
            updatedAt: enteredAt
        )
        let mock = MockAPI()
        await mock.setSessions([running])
        let vm = SessionDetailViewModel(session: running, api: mock)
        #expect(vm.thinkingStartedAt == running.statusEnteredAt)

        await mock.setSessions([waiting])
        await vm.refresh()
        #expect(vm.currentStatus == SessionStatus.awaitingApproval(prompt: "approve"))
        #expect(vm.thinkingStartedAt == enteredAt)

        await vm.refresh()
        #expect(vm.thinkingStartedAt == enteredAt)
    }

    @Test("running のままポーリングしても thinkingStartedAt は変わらない")
    func pollingWhileRunningDoesNotThrash() async {
        let mock = MockAPI()
        await mock.setSessions([session(.running)])
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        let first = vm.thinkingStartedAt
        #expect(first != nil)

        // わずかに時刻を進めてから再 refresh（同一 running）
        try? await Task.sleep(for: .milliseconds(20))
        await mock.setSessions([session(.running)])
        await vm.refresh()
        #expect(vm.thinkingStartedAt == first)
    }

    @Test("recap(now:) は thinkingStartedAt からの経過を使う")
    func recapUsesElapsedFromStartedAt() async throws {
        let mock = MockAPI(
            messagesOutcome: .success([
                .user(id: "u", text: "やって"),
                .command(id: "c", command: "swift build", output: ""),
            ])
        )
        await mock.setSessions([session(.running)])
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        await vm.load()

        let started = try #require(vm.thinkingStartedAt)
        #expect(vm.recap(now: started.addingTimeInterval(2)) == nil)
        #expect(vm.recap(now: started.addingTimeInterval(10)) == "swift build を実行中 · 10 秒")
    }
}
