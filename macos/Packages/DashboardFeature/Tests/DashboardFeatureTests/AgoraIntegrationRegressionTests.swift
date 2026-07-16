// フェーズ4（統合検証）で発見した欠陥のリグレッションテスト（PM 著）。
// 実機討論で「spawn --role 着地の参加者が討論に登録されない」「participantJoined に
// maxAgents ガードが無い」を確認したことに対する固定（decision-log 2026-07-11 参照）。

import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@MainActor
private final class RegressionEffectsRecorder {
    struct Prompt: Equatable {
        let to: SessionID
        let prompt: String
        let submit: Bool
    }

    var prompts: [Prompt] = []
    var summonResults: [SessionID] = []

    func effects() -> AgoraDiscussionCoordinator.Effects {
        AgoraDiscussionCoordinator.Effects(
            send: { _, _, _, _ in true },
            injectPrompt: { [weak self] to, prompt, submit in
                self?.prompts.append(Prompt(to: to, prompt: prompt, submit: submit))
                return true
            },
            summon: { [weak self] _ in
                guard let self, !self.summonResults.isEmpty else { return nil }
                return self.summonResults.removeFirst()
            }
        )
    }
}

@Suite("Agora integration regressions (phase-4)")
@MainActor
struct AgoraIntegrationRegressionTests {
    private func makeCoordinator(
        maxAgents: Int,
        recorder: RegressionEffectsRecorder
    ) async -> (AgoraDiscussionCoordinator, facilitator: SessionID) {
        let facilitator = SessionID()
        recorder.summonResults = [facilitator]
        let config = AgoraDiscussionConfig(
            maxUtterances: 10,
            maxAgents: maxAgents,
            turnTimeoutSeconds: 60,
            consecutiveSpeakLimit: 5,
            stallPassRounds: 9,
            warningRemaining: 0,
            scheduler: .freeSpeech
        )
        let c = AgoraDiscussionCoordinator(config: config, effects: recorder.effects())
        await c.start(agenda: "統合検証の議題", now: at(0))
        return (c, facilitator)
    }

    @Test func 着地登録された参加者には議題と発言規約の参加プロンプトが注入される() async {
        let recorder = RegressionEffectsRecorder()
        let (c, _) = await makeCoordinator(maxAgents: 4, recorder: recorder)
        let joined = SessionID()

        await c.addParticipant(id: joined, role: "批判者", now: at(1))

        #expect(c.participants.contains { $0.id == joined })
        let prompt = recorder.prompts.last
        #expect(prompt?.to == joined)
        #expect(prompt?.submit == true)
        #expect(prompt?.prompt.contains("統合検証の議題") == true)
        #expect(prompt?.prompt.contains("PASS") == true)
        #expect(prompt?.prompt.contains("批判者") == true)
    }

    @Test func maxAgents超過の着地は登録されずプロンプトも注入されない() async {
        let recorder = RegressionEffectsRecorder()
        // maxAgents=2: ファシリテーターで1枠消費済み → 残り1枠。
        let (c, _) = await makeCoordinator(maxAgents: 2, recorder: recorder)
        let a1 = SessionID(), a2 = SessionID()

        await c.addParticipant(id: a1, role: "許容内", now: at(1))
        let promptCountAfterFirst = recorder.prompts.count
        await c.addParticipant(id: a2, role: "超過", now: at(2))

        #expect(c.participants.count == 2)
        #expect(c.participants.contains { $0.id == a1 })
        #expect(!c.participants.contains { $0.id == a2 })
        #expect(recorder.prompts.count == promptCountAfterFirst)  // 超過分への注入なし
    }

    @Test func 役割なしの手動追加参加者にも議題と規約は注入される() async {
        let recorder = RegressionEffectsRecorder()
        let (c, _) = await makeCoordinator(maxAgents: 4, recorder: recorder)
        let joined = SessionID()

        await c.addParticipant(id: joined, role: nil, now: at(1))

        let prompt = recorder.prompts.last
        #expect(prompt?.to == joined)
        #expect(prompt?.prompt.contains("統合検証の議題") == true)
        #expect(prompt?.prompt.contains("PASS") == true)
    }
}
