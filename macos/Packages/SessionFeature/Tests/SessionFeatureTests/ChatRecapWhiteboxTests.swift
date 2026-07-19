import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

/// task-3 白箱: ChatRecap.derive の gate / scope / mapping 境界を網羅。
@Suite("ChatRecap 白箱")
struct ChatRecapWhiteboxTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    var later: Date { t0.addingTimeInterval(10) }
    var atThreshold: Date { t0.addingTimeInterval(ThinkingRecap.defaultThreshold) }
    var below: Date { t0.addingTimeInterval(ThinkingRecap.defaultThreshold - 0.001) }

    func user(_ id: String = "u") -> ChatItem { .userMessage(id: id, text: "hi", timestamp: t0) }
    func reasoning(_ text: String, _ id: String = "r") -> ChatItem {
        .reasoning(id: id, text: text, timestamp: t0)
    }
    func command(_ cmd: String?, _ id: String = "c") -> ChatItem {
        .commandExecution(id: id, command: cmd, output: "", timestamp: t0)
    }
    func file(_ path: String, _ id: String = "f") -> ChatItem {
        .fileChange(id: id, changes: [FilePatchChange(path: path, diff: "")], timestamp: t0)
    }
    func emptyFile(_ id: String = "f0") -> ChatItem {
        .fileChange(id: id, changes: [], timestamp: t0)
    }

    // MARK: - gate

    @Test("status が starting / awaitingApproval / completed / error でも nil")
    func gateNonRunningStatuses() {
        let items = [user(), reasoning("## X")]
        #expect(ChatRecap.derive(transcript: items, status: .starting, turnStartedAt: t0, now: later) == nil)
        #expect(ChatRecap.derive(transcript: items, status: .awaitingApproval(prompt: "p"), turnStartedAt: t0, now: later) == nil)
        #expect(ChatRecap.derive(transcript: items, status: .completed(exitCode: 0), turnStartedAt: t0, now: later) == nil)
        #expect(ChatRecap.derive(transcript: items, status: .error(message: "e"), turnStartedAt: t0, now: later) == nil)
    }

    @Test("閾値ちょうどは通す（elapsed < threshold のみ gate）")
    func gateAtThreshold() {
        let r = ChatRecap.derive(
            transcript: [user(), reasoning("末尾")],
            status: .running,
            turnStartedAt: t0,
            now: atThreshold
        )
        #expect(r == "末尾")
    }

    @Test("閾値未満は nil")
    func gateJustBelowThreshold() {
        #expect(
            ChatRecap.derive(
                transcript: [user(), reasoning("末尾")],
                status: .running,
                turnStartedAt: t0,
                now: below
            ) == nil
        )
    }

    // MARK: - scope

    @Test("userMessage が無いときは transcript 全体が対象")
    func scopeWholeWhenNoUser() {
        let items = [command("swift build"), reasoning("## 設計")]
        // 活動が優先されるので command ラベル
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "swift build を実行中"
        )
    }

    @Test("複数 userMessage があるとき最後の直後だけが対象")
    func scopeAfterLastOfMultipleUsers() {
        let items = [
            user("u1"), command("old"),
            user("u2"), command("ls"),
        ]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "ls を読み込み中"
        )
    }

    // MARK: - mapping

    @Test("reasoning は最新で上書き")
    func reasoningLatestWins() {
        let items = [user(), reasoning("## 古い", "r1"), reasoning("## 新しい", "r2")]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "新しい"
        )
    }

    @Test("activities は古い→新しい順で last が優先")
    func activitiesOldestToNewest() {
        let items = [user(), file("A.swift"), command("rg foo"), command("swift test")]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "swift test を実行中"
        )
    }

    @Test("fileChange で changes が空なら活動に足さない")
    func emptyFileChangeIgnored() {
        let items = [user(), emptyFile(), reasoning("## 見出しだけ")]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "見出しだけ"
        )
    }

    @Test("command nil は RecapActivity.fromCommand に委譲")
    func nilCommandDelegates() {
        let items = [user(), command(nil)]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "コマンド を実行中"
        )
    }

    @Test("agentMessage / error 等は無視")
    func otherCasesIgnored() {
        let items: [ChatItem] = [
            user(),
            .agentMessage(id: "a", text: "hi", timestamp: t0),
            .error(id: "e", message: "boom", timestamp: t0),
            reasoning("## 残る"),
        ]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "残る"
        )
    }

    @Test("活動があれば reasoning より優先")
    func activityBeatsReasoning() {
        let items = [user(), reasoning("## 無視される"), command("cat a")]
        #expect(
            ChatRecap.derive(transcript: items, status: .running, turnStartedAt: t0, now: later)
                == "cat a を読み込み中"
        )
    }

    @Test("カスタム threshold を渡せる")
    func customThreshold() {
        let now = t0.addingTimeInterval(3)
        #expect(
            ChatRecap.derive(
                transcript: [user(), command("x")],
                status: .running,
                turnStartedAt: t0,
                now: now,
                threshold: 5
            ) == nil
        )
        #expect(
            ChatRecap.derive(
                transcript: [user(), command("x")],
                status: .running,
                turnStartedAt: t0,
                now: now,
                threshold: 2
            ) == "x を実行中"
        )
    }
}
