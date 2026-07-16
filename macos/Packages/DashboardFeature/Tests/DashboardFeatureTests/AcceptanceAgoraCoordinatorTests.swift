// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — AgoraDiscussionCoordinator（エンジン⇔実セッション配線）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

// MARK: - fixtures

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@MainActor
private final class EffectsRecorder {
    struct Send: Equatable {
        let from: SessionID?
        let to: SessionID
        let text: String
        let submit: Bool
    }
    struct Prompt: Equatable {
        let to: SessionID
        let prompt: String
        let submit: Bool
    }

    var sends: [Send] = []
    var prompts: [Prompt] = []
    var summonedRoles: [String?] = []
    var summonResults: [SessionID] = []

    func effects() -> AgoraDiscussionCoordinator.Effects {
        AgoraDiscussionCoordinator.Effects(
            send: { [weak self] from, to, text, submit in
                self?.sends.append(Send(from: from, to: to, text: text, submit: submit))
                return true
            },
            injectPrompt: { [weak self] to, prompt, submit in
                self?.prompts.append(Prompt(to: to, prompt: prompt, submit: submit))
                return true
            },
            summon: { [weak self] role in
                guard let self, !self.summonResults.isEmpty else { return nil }
                self.summonedRoles.append(role)
                return self.summonResults.removeFirst()
            }
        )
    }
}

private func smallConfig(
    maxUtterances: Int = 10,
    maxAgents: Int = 4,
    turnTimeoutSeconds: TimeInterval = 60,
    consecutiveSpeakLimit: Int = 5,
    stallPassRounds: Int = 9,
    warningRemaining: Int = 0,
    scheduler: AgoraSchedulerKind = .freeSpeech
) -> AgoraDiscussionConfig {
    AgoraDiscussionConfig(
        maxUtterances: maxUtterances,
        maxAgents: maxAgents,
        turnTimeoutSeconds: turnTimeoutSeconds,
        consecutiveSpeakLimit: consecutiveSpeakLimit,
        stallPassRounds: stallPassRounds,
        warningRemaining: warningRemaining,
        scheduler: scheduler
    )
}

private func snap(
    _ id: SessionID,
    idle: Bool,
    seq: Int,
    _ transcript: [ChatItem]
) -> AgoraDiscussionCoordinator.ParticipantSnapshot {
    AgoraDiscussionCoordinator.ParticipantSnapshot(
        id: id,
        isIdle: idle,
        completedTurnSeq: seq,
        transcript: transcript
    )
}

private func agent(_ id: String, _ text: String) -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: t0)
}

// MARK: - acceptance

@MainActor
@Suite("AgoraDiscussionCoordinator acceptance (task-4)")
struct AcceptanceAgoraCoordinatorTests {

    @Test func start_はファシリテーターを役割付きで招集し議題入りプロンプトを注入する() async {
        let recorder = EffectsRecorder()
        let facilitator = SessionID()
        recorder.summonResults = [facilitator]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())

        await c.start(agenda: "キャッシュ戦略の是非", now: at(0))

        #expect(recorder.summonedRoles.count == 1)
        #expect(recorder.summonedRoles.first != nil)   // 役割必須（ファシリテーター）
        #expect(recorder.prompts.count == 1)
        #expect(recorder.prompts.first?.to == facilitator)
        #expect(recorder.prompts.first?.prompt.contains("キャッシュ戦略の是非") == true)
        #expect(recorder.prompts.first?.prompt.contains("PASS") == true)
        #expect(recorder.prompts.first?.submit == true)
        #expect(c.phase == .discussing)
        #expect(c.participants.count == 1)
        #expect(c.participants.first?.isFacilitator == true)
        #expect(c.agenda == "キャッシュ戦略の是非")
    }

    @Test func turn完了の発言が抽出され_idleの他参加者へ帰属付きで配送される() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: "批判者", now: at(1))

        // F の turn 完了（改行入り発言）→ ログへ
        await c.tick(now: at(2), snapshots: [
            snap(f, idle: true, seq: 1, [agent("f1", "こんにちは\n議論を始めます")]),
            snap(a, idle: false, seq: 0, []),
        ])
        // A が idle → 未読が配送される
        await c.tick(now: at(3), snapshots: [
            snap(f, idle: true, seq: 1, [agent("f1", "こんにちは\n議論を始めます")]),
            snap(a, idle: true, seq: 0, []),
        ])

        let sendsToA = recorder.sends.filter { $0.to == a }
        #expect(sendsToA.count >= 2)  // 発言リレー（1発言=1send）＋最後の発話促し
        #expect(sendsToA.first?.from == f)  // 帰属は発言者の SessionID
        #expect(sendsToA.first?.text == "こんにちは ⏎ 議論を始めます")  // 整形済み1行
        #expect(sendsToA.first?.submit == false)
        #expect(sendsToA.last?.submit == true)  // 発話促しのみ submit
        #expect(c.utteranceCount == 1)
    }

    @Test func 配送境界は前回配送以降のみ_自分の発言は届かない() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))

        let f1 = [agent("f1", "第一声")]
        await c.tick(now: at(2), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: false, seq: 0, [])])
        await c.tick(now: at(3), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: true, seq: 0, [])])  // A へ「第一声」配送
        let a1 = [agent("a1", "了解")]
        await c.tick(now: at(4), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: true, seq: 1, a1)])  // A の応答
        let f2 = f1 + [agent("f2", "第二声")]
        await c.tick(now: at(5), snapshots: [snap(f, idle: true, seq: 2, f2), snap(a, idle: true, seq: 1, a1)])  // F の2発言目
        recorder.sends.removeAll()
        await c.tick(now: at(6), snapshots: [snap(f, idle: true, seq: 2, f2), snap(a, idle: true, seq: 1, a1)])  // A idle → 未読配送

        let sendsToA = recorder.sends.filter { $0.to == a }
        #expect(sendsToA.contains { $0.text.contains("第二声") })
        #expect(!sendsToA.contains { $0.text.contains("第一声") })  // 配送済み
        #expect(!sendsToA.contains { $0.text.contains("了解") })    // 自分の発言
    }

    @Test func PASS応答はリレーされず発言数にも数えない() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))

        let f1 = [agent("f1", "第一声")]
        await c.tick(now: at(2), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: false, seq: 0, [])])
        await c.tick(now: at(3), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: true, seq: 0, [])])  // A へ配送
        recorder.sends.removeAll()
        let aPass = [agent("a1", "PASS")]
        await c.tick(now: at(4), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: true, seq: 1, aPass)])  // A が PASS
        await c.tick(now: at(5), snapshots: [snap(f, idle: true, seq: 1, f1), snap(a, idle: true, seq: 1, aPass)])  // F idle 継続

        #expect(recorder.sends.filter { $0.to == f }.isEmpty)  // PASS は F へ届かない
        #expect(c.utteranceCount == 1)
    }

    @Test func ユーザー発言は参加者へ配送されるが発言数に数えない() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))
        recorder.sends.removeAll()

        await c.submitUserUtterance("皆さんの意見を聞きたい", now: at(2))
        await c.tick(now: at(3), snapshots: [
            snap(f, idle: true, seq: 0, []),
            snap(a, idle: true, seq: 0, []),
        ])

        #expect(recorder.sends.contains { $0.to == f && $0.text.contains("皆さんの意見を聞きたい") && $0.from == nil })
        #expect(recorder.sends.contains { $0.to == a && $0.text.contains("皆さんの意見を聞きたい") && $0.from == nil })
        #expect(c.utteranceCount == 0)
    }

    @Test func 上限到達で_concluding_になりファシリテーターの最終まとめで_ended() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(maxUtterances: 1), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))

        let a1 = [agent("a1", "唯一の発言")]
        await c.tick(now: at(2), snapshots: [snap(f, idle: true, seq: 0, []), snap(a, idle: true, seq: 1, a1)])
        #expect(c.phase == .concluding)
        #expect(recorder.sends.contains { $0.to == f && $0.submit == true })  // まとめ要求が F へ届く

        let fSummary = [agent("f1", "本日のまとめです")]
        await c.tick(now: at(3), snapshots: [snap(f, idle: true, seq: 1, fSummary), snap(a, idle: true, seq: 1, a1)])
        #expect(c.phase == .ended(.utteranceLimitReached))
    }

    @Test func stop_で_ended_になり以後は一切送信しない() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))

        await c.stop(now: at(2))
        #expect(c.phase == .ended(.stopped))
        recorder.sends.removeAll()
        recorder.prompts.removeAll()

        await c.submitUserUtterance("聞こえますか", now: at(3))
        await c.tick(now: at(4), snapshots: [
            snap(f, idle: true, seq: 1, [agent("f1", "遅延発言")]),
            snap(a, idle: true, seq: 0, []),
        ])
        #expect(recorder.sends.isEmpty)
        #expect(recorder.prompts.isEmpty)
    }

    @Test func 同一turnの再観測は二重計上しない() async {
        let recorder = EffectsRecorder()
        let f = SessionID(), a = SessionID()
        recorder.summonResults = [f]
        let c = AgoraDiscussionCoordinator(config: smallConfig(), effects: recorder.effects())
        await c.start(agenda: "議題X", now: at(0))
        await c.addParticipant(id: a, role: nil, now: at(1))

        let f1 = [agent("f1", "一度だけの発言")]
        let snapshots = [snap(f, idle: true, seq: 1, f1), snap(a, idle: false, seq: 0, [])]
        await c.tick(now: at(2), snapshots: snapshots)
        await c.tick(now: at(3), snapshots: snapshots)  // 同じ seq を再観測
        await c.tick(now: at(4), snapshots: snapshots)

        #expect(c.utteranceCount == 1)  // completedTurnSeq が進んだ時だけ計上
    }
}
