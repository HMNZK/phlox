// task-3: アゴラ討論参加者の役割ベース命名 — VM 配線の白箱テスト。

import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
import SessionFeature
@testable import DashboardFeature

@MainActor
private final class SlowDrainEffectsRecorder {
    var summonResults: [SessionID] = []
    var slowInjectSessionID: SessionID?
    private(set) var slowInjectGate: CheckedContinuation<Void, Never>?

    func releaseSlowInject() {
        slowInjectGate?.resume()
        slowInjectGate = nil
    }

    func effects() -> AgoraDiscussionCoordinator.Effects {
        AgoraDiscussionCoordinator.Effects(
            send: { _, _, _, _ in true },
            injectPrompt: { [weak self] to, _, _ in
                guard let self else { return true }
                if to == self.slowInjectSessionID {
                    await withCheckedContinuation { continuation in
                        self.slowInjectGate = continuation
                    }
                }
                return true
            },
            summon: { [weak self] _ in
                guard let self, !self.summonResults.isEmpty else { return nil }
                return self.summonResults.removeFirst()
            }
        )
    }
}

private func renameRaceConfig() -> AgoraDiscussionConfig {
    AgoraDiscussionConfig(
        maxUtterances: 10,
        maxAgents: 4,
        turnTimeoutSeconds: 60,
        consecutiveSpeakLimit: 5,
        stallPassRounds: 9,
        warningRemaining: 0,
        scheduler: .freeSpeech
    )
}

@Suite("Agora participant rename (task-3)")
@MainActor
struct AgoraParticipantRenameTests {
    @Test func addAgoraDiscussionParticipant_登録成立後にセッション名が役割名になる() async throws {
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let started = await dashboard.startAgoraDiscussion(agenda: "テスト議題")
        #expect(started)

        let participantID = try await dashboard.spawnNewSession(kind: .claudeCode)
        let flowerName = try #require(dashboard.sessions.first { $0.id == participantID }?.name)
        #expect(FlowerNameGenerator.names.contains(flowerName))

        await dashboard.addAgoraDiscussionParticipant(id: participantID, role: "批判者")

        #expect(dashboard.agoraDiscussionCoordinator?.participants.contains { $0.id == participantID } == true)
        #expect(dashboard.sessions.first { $0.id == participantID }?.name == "批判者")
    }

    @Test func addAgoraDiscussionParticipant_roleNilでは名前が変わらない() async throws {
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let started = await dashboard.startAgoraDiscussion(agenda: "テスト議題")
        #expect(started)

        let participantID = try await dashboard.spawnNewSession(kind: .claudeCode)
        let flowerName = try #require(dashboard.sessions.first { $0.id == participantID }?.name)

        await dashboard.addAgoraDiscussionParticipant(id: participantID, role: nil)

        #expect(dashboard.agoraDiscussionCoordinator?.participants.contains { $0.id == participantID } == true)
        #expect(dashboard.sessions.first { $0.id == participantID }?.name == flowerName)
    }

    @Test func addParticipant_drain進行中でもawait復帰時にparticipants反映済みでリネーム判定が成立する() async {
        let facilitator = SessionID()
        let slowParticipant = SessionID()
        let fastParticipant = SessionID()
        let recorder = SlowDrainEffectsRecorder()
        recorder.summonResults = [facilitator]
        recorder.slowInjectSessionID = slowParticipant

        let coordinator = AgoraDiscussionCoordinator(
            config: renameRaceConfig(),
            effects: recorder.effects()
        )
        await coordinator.start(agenda: "レース検証", now: Date())

        let slowAddTask = Task { @MainActor in
            await coordinator.addParticipant(id: slowParticipant, role: "遅い参加者", now: Date())
        }

        while recorder.slowInjectGate == nil {
            await Task.yield()
        }

        // drain は slowInject のゲートで塞がれている。この間に投入した addParticipant は
        // 「自分の操作が処理されるまで」await が復帰しないこと（＝復帰時点で participants
        // 反映済み）が修正後の契約。ゲート解放は並行タスクで行う（await の後に書くと
        // 循環待ちでデッドロックする — 修正前はここで取りこぼしが起きていた）。
        let fastAddTask = Task { @MainActor in
            await coordinator.addParticipant(id: fastParticipant, role: "批判者", now: Date())
        }

        // fast の enqueue が積まれるのを待ってからゲートを解放する。
        await Task.yield()
        #expect(!coordinator.participants.contains { $0.id == fastParticipant })  // まだ処理前
        recorder.releaseSlowInject()

        await fastAddTask.value
        #expect(coordinator.participants.contains { $0.id == fastParticipant })

        await slowAddTask.value
        #expect(coordinator.participants.contains { $0.id == slowParticipant })
    }

    @Test func addAgoraDiscussionParticipant_同一参加者の再登録で名前が繰り上がらない() async throws {
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let started = await dashboard.startAgoraDiscussion(agenda: "テスト議題")
        #expect(started)

        let participantID = try await dashboard.spawnNewSession(kind: .claudeCode)
        await dashboard.addAgoraDiscussionParticipant(id: participantID, role: "批判者")
        #expect(dashboard.sessions.first { $0.id == participantID }?.name == "批判者")

        await dashboard.addAgoraDiscussionParticipant(id: participantID, role: "批判者")
        #expect(dashboard.sessions.first { $0.id == participantID }?.name == "批判者")
    }
}
