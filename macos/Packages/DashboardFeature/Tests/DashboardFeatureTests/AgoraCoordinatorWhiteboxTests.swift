import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private let whiteboxT0 = Date(timeIntervalSince1970: 2_000_000)
private func whiteboxAt(_ seconds: TimeInterval) -> Date {
    whiteboxT0.addingTimeInterval(seconds)
}

@MainActor
private final class WhiteboxEffects {
    struct Send: Equatable {
        let from: SessionID?
        let to: SessionID
        let text: String
        let submit: Bool
    }

    var sends: [Send] = []
    var prompts: [(SessionID, String, Bool)] = []
    var summonResults: [SessionID] = []
    var onSend: ((_ send: Send) async -> Void)?

    func effects() -> AgoraDiscussionCoordinator.Effects {
        AgoraDiscussionCoordinator.Effects(
            send: { [weak self] from, to, text, submit in
                guard let self else { return false }
                let send = Send(from: from, to: to, text: text, submit: submit)
                self.sends.append(send)
                await self.onSend?(send)
                return true
            },
            injectPrompt: { [weak self] to, prompt, submit in
                self?.prompts.append((to, prompt, submit))
                return true
            },
            summon: { [weak self] _ in
                guard let self, !self.summonResults.isEmpty else { return nil }
                return self.summonResults.removeFirst()
            }
        )
    }
}

private func whiteboxConfig(
    turnTimeoutSeconds: TimeInterval = 60
) -> AgoraDiscussionConfig {
    AgoraDiscussionConfig(
        maxUtterances: 10,
        maxAgents: 4,
        turnTimeoutSeconds: turnTimeoutSeconds,
        consecutiveSpeakLimit: 5,
        stallPassRounds: 9,
        warningRemaining: 0,
        scheduler: .freeSpeech
    )
}

private func whiteboxSnap(
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

private func whiteboxAgent(_ id: String, _ text: String) -> ChatItem {
    .agentMessage(id: id, text: text, timestamp: whiteboxT0)
}

@MainActor
@Suite("AgoraDiscussionCoordinator whitebox (task-4)")
struct AgoraCoordinatorWhiteboxTests {
    @Test func deliver実行中に到着したturn完了は配送完了後まで直列化される() async {
        let effects = WhiteboxEffects()
        let f = SessionID()
        let a = SessionID()
        effects.summonResults = [f]
        let coordinator = AgoraDiscussionCoordinator(config: whiteboxConfig(), effects: effects.effects())
        await coordinator.start(agenda: "議題", now: whiteboxAt(0))
        await coordinator.addParticipant(id: a, role: nil, now: whiteboxAt(1))

        await coordinator.tick(now: whiteboxAt(2), snapshots: [
            whiteboxSnap(f, idle: true, seq: 1, [whiteboxAgent("f1", "第一声")]),
            whiteboxSnap(a, idle: false, seq: 0, []),
        ])

        var didInjectReentrantTick = false
        effects.onSend = { send in
            guard !didInjectReentrantTick, send.to == a, send.text.contains("第一声") else { return }
            didInjectReentrantTick = true
            await coordinator.tick(now: whiteboxAt(3), snapshots: [
                whiteboxSnap(f, idle: true, seq: 1, [whiteboxAgent("f1", "第一声")]),
                whiteboxSnap(a, idle: true, seq: 1, [whiteboxAgent("a1", "応答")]),
            ])
            #expect(coordinator.utteranceCount == 1)
        }

        await coordinator.tick(now: whiteboxAt(4), snapshots: [
            whiteboxSnap(f, idle: true, seq: 1, [whiteboxAgent("f1", "第一声")]),
            whiteboxSnap(a, idle: true, seq: 0, []),
        ])

        #expect(didInjectReentrantTick)
        #expect(coordinator.utteranceCount == 2)
    }

    @Test func timeoutCheck後にawaiting中参加者へ新しい未読を配送できる() async {
        let effects = WhiteboxEffects()
        let f = SessionID()
        let a = SessionID()
        effects.summonResults = [f]
        let coordinator = AgoraDiscussionCoordinator(
            config: whiteboxConfig(turnTimeoutSeconds: 1),
            effects: effects.effects()
        )
        await coordinator.start(agenda: "議題", now: whiteboxAt(0))
        await coordinator.addParticipant(id: a, role: nil, now: whiteboxAt(1))

        await coordinator.submitUserUtterance("最初の問い", now: whiteboxAt(2))
        await coordinator.tick(now: whiteboxAt(3), snapshots: [
            whiteboxSnap(f, idle: true, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 0, []),
        ])
        effects.sends.removeAll()

        await coordinator.submitUserUtterance("追加の問い", now: whiteboxAt(4))
        await coordinator.tick(now: whiteboxAt(4.5), snapshots: [
            whiteboxSnap(f, idle: true, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 0, []),
        ])
        #expect(!effects.sends.contains { $0.to == f && $0.text.contains("追加の問い") })

        await coordinator.tick(now: whiteboxAt(5.1), snapshots: [
            whiteboxSnap(f, idle: true, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 0, []),
        ])
        await coordinator.tick(now: whiteboxAt(5.2), snapshots: [
            whiteboxSnap(f, idle: true, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 0, []),
        ])

        #expect(effects.sends.contains { $0.to == f && $0.text.contains("追加の問い") })
    }

    @Test func transcript丸ごと置換時は過去発言を再配送せず境界を末尾へリセットする() async {
        let effects = WhiteboxEffects()
        let f = SessionID()
        let a = SessionID()
        effects.summonResults = [f]
        let coordinator = AgoraDiscussionCoordinator(config: whiteboxConfig(), effects: effects.effects())
        await coordinator.start(agenda: "議題", now: whiteboxAt(0))
        await coordinator.addParticipant(id: a, role: nil, now: whiteboxAt(1))

        // a が正規の発言を1つ完了 → 抽出され境界 itemID が "a1" になる（f は idle=false で未配送・cursor 温存）。
        await coordinator.tick(now: whiteboxAt(2), snapshots: [
            whiteboxSnap(f, idle: false, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 1, [whiteboxAgent("a1", "意見アルファ")]),
        ])
        #expect(coordinator.utteranceCount == 1)

        // transcript が丸ごと置換される（revert/rebuild で itemID が総入れ替え → 境界 "a1" が消失）。
        // 全件フォールバック抽出が起きると過去内容「意見アルファ／意見ベータ」が1発言として再計上・再配送される。
        await coordinator.tick(now: whiteboxAt(3), snapshots: [
            whiteboxSnap(f, idle: false, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 2, [
                whiteboxAgent("r1", "意見アルファ"),
                whiteboxAgent("r2", "意見ベータ"),
            ]),
        ])
        // 置換検知 → 抽出せずスキップ。再計上されない。
        #expect(coordinator.utteranceCount == 1)

        // 境界は末尾 "r2" へリセットされている: 続けて追記された新発言のみが抽出される（"意見ベータ" は再配送されない）。
        await coordinator.tick(now: whiteboxAt(4), snapshots: [
            whiteboxSnap(f, idle: false, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 3, [
                whiteboxAgent("r1", "意見アルファ"),
                whiteboxAgent("r2", "意見ベータ"),
                whiteboxAgent("r3", "意見ガンマ"),
            ]),
        ])
        #expect(coordinator.utteranceCount == 2)

        // f が idle → 討論ログの正規発言だけが配送される。置換された "意見ベータ" は一度もログに入らず届かない。
        await coordinator.tick(now: whiteboxAt(5), snapshots: [
            whiteboxSnap(f, idle: true, seq: 0, []),
            whiteboxSnap(a, idle: false, seq: 3, [
                whiteboxAgent("r1", "意見アルファ"),
                whiteboxAgent("r2", "意見ベータ"),
                whiteboxAgent("r3", "意見ガンマ"),
            ]),
        ])
        #expect(effects.sends.contains { $0.to == f && $0.text.contains("意見ガンマ") })
        #expect(!effects.sends.contains { $0.to == f && $0.text.contains("意見ベータ") })
    }
}
