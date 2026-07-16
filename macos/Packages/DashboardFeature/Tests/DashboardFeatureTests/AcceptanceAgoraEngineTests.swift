// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — AgoraDiscussionEngine 純粋状態機械（自由発言＋roundRobin）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// MARK: - fixtures

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func smallConfig(
    maxUtterances: Int = 5,
    maxAgents: Int = 3,
    turnTimeoutSeconds: TimeInterval = 60,
    consecutiveSpeakLimit: Int = 2,
    stallPassRounds: Int = 1,
    warningRemaining: Int = 2,
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

/// F（ファシリテーター）＋A・B の3人討論を組み立てる標準ハーネス。
private struct Arena {
    var engine: AgoraDiscussionEngine
    let f = SessionID()
    let a = SessionID()
    let b = SessionID()

    init(config: AgoraDiscussionConfig, joinAB: Bool = true) {
        engine = AgoraDiscussionEngine(config: config)
        _ = engine.apply(.started(agenda: "議題X", facilitatorID: f, facilitatorRole: "ファシリテーター", now: at(0)))
        if joinAB {
            _ = engine.apply(.participantJoined(id: a, role: "批判者", now: at(1)))
            _ = engine.apply(.participantJoined(id: b, role: "推進者", now: at(1)))
        }
    }

    mutating func apply(_ e: AgoraDiscussionEvent) -> [AgoraDiscussionCommand] {
        engine.apply(e)
    }
}

private func deliverCommands(_ commands: [AgoraDiscussionCommand]) -> [(to: SessionID, entries: [AgoraLogEntry], notice: String?, promptSpeak: Bool)] {
    commands.compactMap {
        if case .deliver(let to, let entries, let notice, let promptSpeak) = $0 {
            return (to, entries, notice, promptSpeak)
        }
        return nil
    }
}

// MARK: - 開始と参加

@Suite("AgoraDiscussionEngine acceptance (task-1)")
struct AcceptanceAgoraEngineTests {

    @Test func started_で_discussing_になりファシリテーターが参加者に載る() {
        var arena = Arena(config: smallConfig(), joinAB: false)
        #expect(arena.engine.phase == .discussing)
        #expect(arena.engine.participants.count == 1)
        #expect(arena.engine.participants.first?.id == arena.f)
        #expect(arena.engine.participants.first?.isFacilitator == true)
        #expect(arena.engine.agenda == "議題X")
    }

    @Test func 実発言は_seq_1始まり欠番なしでログに追記される() throws {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.userUtterance(text: "ユーザー補足", now: at(3)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "反論", isPass: false, now: at(4)))
        try #require(arena.engine.log.count == 3)
        #expect(arena.engine.log.map(\.seq) == [1, 2, 3])
        #expect(arena.engine.log.map(\.text) == ["開会", "ユーザー補足", "反論"])
        #expect(arena.engine.log[0].speaker == .session(arena.f))
        #expect(arena.engine.log[1].speaker == .user)
        #expect(arena.engine.utteranceCount == 2)  // ユーザー発言は数えない
    }

    // MARK: - 自由発言の配送（idle ゲート・未読カーソル）

    @Test func idle_の参加者へ未読が一括配送されカーソルが進む() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.userUtterance(text: "補足", now: at(3)))
        let commands = arena.apply(.participantBecameIdle(id: arena.a, now: at(4)))
        let delivers = deliverCommands(commands)
        #expect(delivers.count == 1)
        #expect(delivers.first?.to == arena.a)
        #expect(delivers.first?.entries.map(\.seq) == [1, 2])
        #expect(delivers.first?.promptSpeak == true)
        let cursorA = arena.engine.participants.first { $0.id == arena.a }?.cursor
        #expect(cursorA == 2)
    }

    @Test func 自分の発言だけの未読では配送しない() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "自分の発言", isPass: false, now: at(2)))
        let commands = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        #expect(deliverCommands(commands).isEmpty)
    }

    @Test func 配送で_awaiting_になり完了までは再配送しない() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        _ = arena.apply(.utteranceCompleted(id: arena.b, text: "新規発言", isPass: false, now: at(4)))
        let second = arena.apply(.participantBecameIdle(id: arena.a, now: at(5)))
        #expect(deliverCommands(second).isEmpty)  // awaiting 中は未読があっても再配送しない
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "応答", isPass: false, now: at(6)))
        let third = arena.apply(.participantBecameIdle(id: arena.a, now: at(7)))
        #expect(deliverCommands(third).count == 1)  // 完了で awaiting 解除→未読（Bの発言）を配送
        #expect(deliverCommands(third).first?.entries.map(\.text) == ["新規発言"])
    }

    @Test func 途中参加者のカーソルはログ末尾から始まり過去ログを受け取らない() {
        var arena = Arena(config: smallConfig(maxAgents: 4), joinAB: true)
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        let c = SessionID()
        _ = arena.apply(.participantJoined(id: c, role: nil, now: at(3)))
        let commands = arena.apply(.participantBecameIdle(id: c, now: at(4)))
        #expect(deliverCommands(commands).isEmpty)
        let cursorC = arena.engine.participants.first { $0.id == c }?.cursor
        #expect(cursorC == 1)
    }

    // MARK: - PASS と停滞

    @Test func PASS_はログに載らず発言数にも数えない() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(4)))
        #expect(arena.engine.log.count == 1)
        #expect(arena.engine.utteranceCount == 1)
    }

    @Test func 連続PASSが閾値に達するとファシリテーターへ停滞打開のdeliverが出る() {
        // stallPassRounds=1・参加者3人 → (3-1)*1 = 2 連続 PASS で発火
        var arena = Arena(config: smallConfig(stallPassRounds: 1))
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        _ = arena.apply(.participantBecameIdle(id: arena.b, now: at(3)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(4)))
        let commands = arena.apply(.utteranceCompleted(id: arena.b, text: "PASS", isPass: true, now: at(5)))
        let delivers = deliverCommands(commands).filter { $0.to == arena.f }
        #expect(delivers.count == 1)
        #expect(delivers.first?.notice != nil)
        #expect(delivers.first?.promptSpeak == true)
    }

    // MARK: - キャップ（残数警告・上限終了）

    @Test func 残数が_warningRemaining_以下になると配送noticeに警告が付く() {
        // maxUtterances=5, warningRemaining=2 → 3発言目以降（残り2）の deliver は notice 付き
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "u1", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))  // 残り4: notice なし
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "u2", isPass: false, now: at(4)))
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "u3", isPass: false, now: at(5)))
        let commands = arena.apply(.participantBecameIdle(id: arena.b, now: at(6)))  // 残り2: notice 付き
        let delivers = deliverCommands(commands)
        #expect(delivers.count == 1)
        #expect(delivers.first?.notice != nil)
    }

    @Test func 残数が警告閾値より多い間の配送はnoticeなし() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "u1", isPass: false, now: at(2)))
        let commands = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        #expect(deliverCommands(commands).first?.notice == nil)
    }

    @Test func 上限到達で_concluding_になり_requestConclusion_が出て新規配送が止まる() {
        var arena = Arena(config: smallConfig(maxUtterances: 2, warningRemaining: 1))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "u1", isPass: false, now: at(2)))
        let atCap = arena.apply(.utteranceCompleted(id: arena.b, text: "u2", isPass: false, now: at(3)))
        let conclusionRequests = atCap.filter {
            if case .requestConclusion(let to, _) = $0 { return to == arena.f }
            return false
        }
        #expect(conclusionRequests.count == 1)
        #expect(arena.engine.phase == .concluding)
        let commands = arena.apply(.participantBecameIdle(id: arena.a, now: at(4)))
        #expect(deliverCommands(commands).isEmpty)  // concluding 中は新規配送なし
    }

    @Test func concluding_中のファシリテーター発言で_end_utteranceLimitReached() {
        var arena = Arena(config: smallConfig(maxUtterances: 1, warningRemaining: 0))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "u1", isPass: false, now: at(2)))
        let commands = arena.apply(.utteranceCompleted(id: arena.f, text: "まとめ", isPass: false, now: at(3)))
        #expect(commands.contains(.end(.utteranceLimitReached)))
        #expect(arena.engine.phase == .ended(.utteranceLimitReached))
        #expect(arena.engine.log.last?.text == "まとめ")  // 最終まとめはログに載る
    }

    // MARK: - 連続発言制限

    @Test func 連続発言が上限に達した参加者への配送は_promptSpeak_false_になり他者の発言で回復する() {
        var arena = Arena(config: smallConfig(maxUtterances: 20, stallPassRounds: 9, warningRemaining: 0))
        // A が連続2回発言（間はユーザー発言のみ＝リセットされない）
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "a1", isPass: false, now: at(4)))
        _ = arena.apply(.userUtterance(text: "なるほど", now: at(5)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(6)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "a2", isPass: false, now: at(7)))
        _ = arena.apply(.userUtterance(text: "ふむ", now: at(8)))
        let muted = arena.apply(.participantBecameIdle(id: arena.a, now: at(9)))
        #expect(deliverCommands(muted).first?.promptSpeak == false)  // 上限到達: 配送はするが促さない
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(10)))
        // 他エージェント B の実発言でリセット
        _ = arena.apply(.utteranceCompleted(id: arena.b, text: "b1", isPass: false, now: at(11)))
        let recovered = arena.apply(.participantBecameIdle(id: arena.a, now: at(12)))
        #expect(deliverCommands(recovered).first?.promptSpeak == true)
    }

    // MARK: - 招集

    @Test func 招集は上限未満なら_summon_上限で_rejectSummon() {
        var arena = Arena(config: smallConfig(maxAgents: 3), joinAB: false)
        _ = arena.apply(.participantJoined(id: arena.a, role: "批判者", now: at(1)))
        let ok = arena.apply(.summonRequested(role: "推進者", now: at(2)))
        #expect(ok.contains(.summon(role: "推進者")))
        _ = arena.apply(.participantJoined(id: arena.b, role: "推進者", now: at(3)))
        let rejected = arena.apply(.summonRequested(role: "観察者", now: at(4)))
        let rejects = rejected.filter {
            if case .rejectSummon(let role, _) = $0 { return role == "観察者" }
            return false
        }
        #expect(rejects.count == 1)
        #expect(arena.engine.participants.count == 3)
    }

    // MARK: - タイムアウト

    @Test func タイムアウトで_awaiting_が解除され再配送が可能になる() {
        var arena = Arena(config: smallConfig(turnTimeoutSeconds: 60))
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.a, now: at(3)))  // 配送→awaiting
        _ = arena.apply(.timeoutCheck(now: at(30)))  // 60秒未満: 解除されない
        _ = arena.apply(.utteranceCompleted(id: arena.b, text: "b1", isPass: false, now: at(31)))
        let still = arena.apply(.participantBecameIdle(id: arena.a, now: at(32)))
        #expect(deliverCommands(still).isEmpty)
        _ = arena.apply(.timeoutCheck(now: at(70)))  // 60秒超過: awaiting 解除
        let resumed = arena.apply(.participantBecameIdle(id: arena.a, now: at(71)))
        #expect(deliverCommands(resumed).count == 1)
        #expect(deliverCommands(resumed).first?.entries.map(\.text) == ["b1"])
    }

    // MARK: - 停止と終了後

    @Test func stopRequested_で_end_stopped_し以後のイベントは空で状態不変() {
        var arena = Arena(config: smallConfig())
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        let commands = arena.apply(.stopRequested(now: at(3)))
        #expect(commands.contains(.end(.stopped)))
        #expect(arena.engine.phase == .ended(.stopped))
        let logCount = arena.engine.log.count
        let after = arena.apply(.utteranceCompleted(id: arena.a, text: "遅延", isPass: false, now: at(4)))
        #expect(after.isEmpty)
        #expect(arena.engine.log.count == logCount)
        let idleAfter = arena.apply(.participantBecameIdle(id: arena.b, now: at(5)))
        #expect(idleAfter.isEmpty)
    }

    // MARK: - 停滞通知と配送不変条件の整合（stage2 差し戻し1回目で追加凍結）

    @Test func awaiting中のファシリテーターへ停滞deliverを再配送しない() {
        var arena = Arena(config: smallConfig(stallPassRounds: 1))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "a1", isPass: false, now: at(2)))
        #expect(deliverCommands(arena.apply(.participantBecameIdle(id: arena.f, now: at(3)))).count == 1)
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(4)))
        let commands = arena.apply(.utteranceCompleted(id: arena.b, text: "PASS", isPass: true, now: at(5)))
        #expect(deliverCommands(commands).isEmpty)  // F は awaiting 中: 停滞 deliver も再配送禁止
    }

    @Test func 抑止された停滞通知はファシリテーターの次のidle配送で届く() {
        var arena = Arena(config: smallConfig(stallPassRounds: 1))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "a1", isPass: false, now: at(2)))
        _ = arena.apply(.participantBecameIdle(id: arena.f, now: at(3)))  // F へ a1 配送→awaiting
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(4)))
        _ = arena.apply(.utteranceCompleted(id: arena.b, text: "PASS", isPass: true, now: at(5)))  // 閾値到達（F awaiting につき抑止）
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "PASS", isPass: true, now: at(6)))  // F 完了（awaiting 解除・停滞は未解消）
        let commands = arena.apply(.participantBecameIdle(id: arena.f, now: at(7)))
        let delivers = deliverCommands(commands)
        #expect(delivers.count == 1)  // 未読ゼロでも停滞 notice のみで発火
        #expect(delivers.first?.notice?.contains("停滞") == true)
        #expect(delivers.first?.promptSpeak == true)
    }

    @Test func 警告閾値後の停滞deliverには残数警告も合成される() {
        var arena = Arena(config: smallConfig(maxUtterances: 3, stallPassRounds: 1, warningRemaining: 2))
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "u1", isPass: false, now: at(2)))
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(3)))
        let commands = arena.apply(.utteranceCompleted(id: arena.b, text: "PASS", isPass: true, now: at(4)))
        let notice = deliverCommands(commands).first?.notice
        #expect(notice?.contains("残り") == true)
        #expect(notice?.contains("停滞") == true)
    }

    @Test func 保留停滞通知は連続発言制限中の配送でも_promptSpeak_true() {
        // 停滞打開の nudge は独占防止より優先する（false だと誰も促されず討論が固まる）
        var arena = Arena(config: smallConfig(consecutiveSpeakLimit: 1, stallPassRounds: 1))
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "f1", isPass: false, now: at(2)))  // F consec=1（上限）
        _ = arena.apply(.userUtterance(text: "補足", now: at(3)))  // ユーザー発言は consec をリセットしない
        _ = arena.apply(.participantBecameIdle(id: arena.f, now: at(4)))  // F へ配送→awaiting
        _ = arena.apply(.utteranceCompleted(id: arena.a, text: "PASS", isPass: true, now: at(5)))
        _ = arena.apply(.utteranceCompleted(id: arena.b, text: "PASS", isPass: true, now: at(6)))  // 閾値到達→保留
        _ = arena.apply(.utteranceCompleted(id: arena.f, text: "PASS", isPass: true, now: at(7)))  // awaiting 解除
        let delivers = deliverCommands(arena.apply(.participantBecameIdle(id: arena.f, now: at(8))))
        #expect(delivers.first?.notice?.contains("停滞") == true)
        #expect(delivers.first?.promptSpeak == true)
    }

    // MARK: - roundRobin fallback

    @Test func roundRobin_は実発言の完了駆動で参加順の次の1名にのみ配送する() {
        var arena = Arena(config: smallConfig(scheduler: .roundRobin))
        // F の発言完了 → 参加順（F→A→B）で次の A のみへ配送
        let afterF = arena.apply(.utteranceCompleted(id: arena.f, text: "開会", isPass: false, now: at(2)))
        let deliversF = deliverCommands(afterF)
        #expect(deliversF.count == 1)
        #expect(deliversF.first?.to == arena.a)
        #expect(deliversF.first?.entries.map(\.seq) == [1])
        #expect(deliversF.first?.promptSpeak == true)
        // A の発言完了 → B へ
        let afterA = arena.apply(.utteranceCompleted(id: arena.a, text: "a1", isPass: false, now: at(3)))
        #expect(deliverCommands(afterA).first?.to == arena.b)
        // idle イベントは roundRobin では配送を起こさない
        let idle = arena.apply(.participantBecameIdle(id: arena.f, now: at(4)))
        #expect(deliverCommands(idle).isEmpty)
    }
}
