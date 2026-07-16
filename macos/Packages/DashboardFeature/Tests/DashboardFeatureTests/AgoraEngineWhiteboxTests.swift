import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

private let agoraWhiteboxT0 = Date(timeIntervalSince1970: 2_000_000)
private func agoraWhiteboxAt(_ seconds: TimeInterval) -> Date {
    agoraWhiteboxT0.addingTimeInterval(seconds)
}

private func agoraWhiteboxConfig(
    maxUtterances: Int = 5,
    turnTimeoutSeconds: TimeInterval = 60
) -> AgoraDiscussionConfig {
    AgoraDiscussionConfig(
        maxUtterances: maxUtterances,
        maxAgents: 3,
        turnTimeoutSeconds: turnTimeoutSeconds,
        consecutiveSpeakLimit: 2,
        stallPassRounds: 2,
        warningRemaining: 1,
        scheduler: .freeSpeech
    )
}

private func agoraWhiteboxDelivers(_ commands: [AgoraDiscussionCommand]) -> [AgoraDiscussionCommand] {
    commands.filter {
        if case .deliver = $0 {
            return true
        }
        return false
    }
}

@Suite("AgoraDiscussionEngine whitebox (task-1)")
struct AgoraEngineWhiteboxTests {
    @Test func awaiting中のidle再着は未読が増えても二重配送しない() {
        var engine = AgoraDiscussionEngine(config: agoraWhiteboxConfig())
        let facilitator = SessionID()
        let a = SessionID()
        let b = SessionID()
        _ = engine.apply(.started(agenda: "agenda", facilitatorID: facilitator, facilitatorRole: nil, now: agoraWhiteboxAt(0)))
        _ = engine.apply(.participantJoined(id: a, role: nil, now: agoraWhiteboxAt(1)))
        _ = engine.apply(.participantJoined(id: b, role: nil, now: agoraWhiteboxAt(1)))
        _ = engine.apply(.utteranceCompleted(id: facilitator, text: "f1", isPass: false, now: agoraWhiteboxAt(2)))
        #expect(agoraWhiteboxDelivers(engine.apply(.participantBecameIdle(id: a, now: agoraWhiteboxAt(3)))).count == 1)
        _ = engine.apply(.utteranceCompleted(id: b, text: "b1", isPass: false, now: agoraWhiteboxAt(4)))

        let commands = engine.apply(.participantBecameIdle(id: a, now: agoraWhiteboxAt(5)))

        #expect(agoraWhiteboxDelivers(commands).isEmpty)
        #expect(engine.participants.first { $0.id == a }?.awaitingUtteranceSince != nil)
    }

    @Test func 上限到達後のinFlight発言はログに載るが新規配送しない() {
        var engine = AgoraDiscussionEngine(config: agoraWhiteboxConfig(maxUtterances: 2))
        let facilitator = SessionID()
        let a = SessionID()
        let b = SessionID()
        _ = engine.apply(.started(agenda: "agenda", facilitatorID: facilitator, facilitatorRole: nil, now: agoraWhiteboxAt(0)))
        _ = engine.apply(.participantJoined(id: a, role: nil, now: agoraWhiteboxAt(1)))
        _ = engine.apply(.participantJoined(id: b, role: nil, now: agoraWhiteboxAt(1)))
        _ = engine.apply(.utteranceCompleted(id: a, text: "a1", isPass: false, now: agoraWhiteboxAt(2)))
        _ = engine.apply(.participantBecameIdle(id: b, now: agoraWhiteboxAt(3)))
        let capCommands = engine.apply(.utteranceCompleted(id: a, text: "a2", isPass: false, now: agoraWhiteboxAt(4)))

        let lateCommands = engine.apply(.utteranceCompleted(id: b, text: "b1", isPass: false, now: agoraWhiteboxAt(5)))

        #expect(capCommands.contains { if case .requestConclusion = $0 { true } else { false } })
        #expect(engine.log.map(\.text) == ["a1", "a2", "b1"])
        #expect(agoraWhiteboxDelivers(lateCommands).isEmpty)
        #expect(engine.phase == .concluding)
    }

    @Test func ended後の全イベントは空で状態を変えない() {
        var engine = AgoraDiscussionEngine(config: agoraWhiteboxConfig(maxUtterances: 1))
        let facilitator = SessionID()
        let a = SessionID()
        _ = engine.apply(.started(agenda: "agenda", facilitatorID: facilitator, facilitatorRole: nil, now: agoraWhiteboxAt(0)))
        _ = engine.apply(.participantJoined(id: a, role: nil, now: agoraWhiteboxAt(1)))
        _ = engine.apply(.stopRequested(now: agoraWhiteboxAt(2)))
        let phase = engine.phase
        let log = engine.log
        let participants = engine.participants
        let utteranceCount = engine.utteranceCount

        let events: [AgoraDiscussionEvent] = [
            .started(agenda: "new", facilitatorID: SessionID(), facilitatorRole: nil, now: agoraWhiteboxAt(3)),
            .participantJoined(id: SessionID(), role: nil, now: agoraWhiteboxAt(4)),
            .summonRequested(role: nil, now: agoraWhiteboxAt(5)),
            .utteranceCompleted(id: a, text: "late", isPass: false, now: agoraWhiteboxAt(6)),
            .userUtterance(text: "late user", now: agoraWhiteboxAt(7)),
            .participantBecameIdle(id: a, now: agoraWhiteboxAt(8)),
            .timeoutCheck(now: agoraWhiteboxAt(9)),
            .stopRequested(now: agoraWhiteboxAt(10))
        ]

        for event in events {
            #expect(engine.apply(event).isEmpty)
            #expect(engine.phase == phase)
            #expect(engine.log == log)
            #expect(engine.participants == participants)
            #expect(engine.utteranceCount == utteranceCount)
        }
    }
}
