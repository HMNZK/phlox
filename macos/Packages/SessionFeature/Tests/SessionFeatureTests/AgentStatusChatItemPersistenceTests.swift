import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

// エージェント状態カードのために ChatItem へ足した省略可能フィールド
// （agent-status-card-design.md §2）。保存して読み直せること、旧版の JSON を読めること、
// 値だけが違う item を同じものと見なさないこと（appendOrReplace が書き換えを捨てない）、
// モバイル向け差分取得の署名が変わること。

private let started = Date(timeIntervalSinceReferenceDate: 1_000)
private let finished = Date(timeIntervalSinceReferenceDate: 1_007)

private func roundTrip(_ item: ChatItem) throws -> ChatItem {
    try JSONDecoder().decode(ChatItem.self, from: JSONEncoder().encode(item))
}

private func patch() -> StructuredChatKit.FilePatchChange {
    StructuredChatKit.FilePatchChange(path: "api.swift", diff: "+let x = 1", kind: "update")
}

// MARK: - 往復

@Test func commandExecutionKeepsCompletedAtAndIntentAcrossSaveAndLoad() throws {
    let item = ChatItem.commandExecution(
        id: "c1", command: "swift test", output: "ok", timestamp: started,
        completedAt: finished, intent: "テストを実行する"
    )

    let decoded = try roundTrip(item)

    guard case .commandExecution(_, _, _, _, let completedAt, let intent) = decoded else {
        Issue.record("commandExecution のまま読み直せない: \(decoded)")
        return
    }
    #expect(completedAt == finished)
    #expect(intent == "テストを実行する")
}

@Test func fileChangeKeepsCompletedAtAcrossSaveAndLoad() throws {
    let item = ChatItem.fileChange(id: "f1", changes: [patch()], timestamp: started, completedAt: finished)

    let decoded = try roundTrip(item)

    guard case .fileChange(_, _, _, let completedAt) = decoded else {
        Issue.record("fileChange のまま読み直せない: \(decoded)")
        return
    }
    #expect(completedAt == finished)
}

@Test func userMessageKeepsTurnEndAcrossSaveAndLoad() throws {
    let item = ChatItem.userMessage(
        id: "u1", text: "直して", timestamp: started, attachments: [],
        turnEnd: ChatTurnEnd(outcome: .superseded, at: finished)
    )

    let decoded = try roundTrip(item)

    guard case .userMessage(_, _, _, _, let turnEnd) = decoded else {
        Issue.record("userMessage のまま読み直せない: \(decoded)")
        return
    }
    #expect(turnEnd == ChatTurnEnd(outcome: .superseded, at: finished))
}

@Test(arguments: [ChatTurnEnd.Outcome.completed, .interrupted, .error, .superseded])
func turnEndOutcomeSurvivesSaveAndLoad(outcome: ChatTurnEnd.Outcome) throws {
    let item = ChatItem.userMessage(
        id: "u", text: "t", timestamp: started, attachments: [],
        turnEnd: ChatTurnEnd(outcome: outcome, at: finished)
    )

    guard case .userMessage(_, _, _, _, let turnEnd) = try roundTrip(item) else {
        Issue.record("userMessage のまま読み直せない: \(outcome)")
        return
    }
    #expect(turnEnd?.outcome == outcome)
}

// MARK: - 旧版の JSON

@Test func jsonWrittenBeforeTheFeatureLoadsWithEmptyNewFields() throws {
    let command = #"{"commandExecution":{"id":"c1","command":"ls","output":"a","timestamp":1000}}"#
    let change = #"{"fileChange":{"id":"f1","changes":[{"path":"api.swift","diff":"+x"}],"timestamp":1000}}"#
    let user = #"{"userMessage":{"id":"u1","text":"直して","timestamp":1000}}"#

    let decodedCommand = try JSONDecoder().decode(ChatItem.self, from: Data(command.utf8))
    let decodedChange = try JSONDecoder().decode(ChatItem.self, from: Data(change.utf8))
    let decodedUser = try JSONDecoder().decode(ChatItem.self, from: Data(user.utf8))

    guard case .commandExecution(let id, let text, let output, _, let completedAt, let intent) = decodedCommand,
          case .fileChange(let changeID, _, _, let changeCompletedAt) = decodedChange,
          case .userMessage(let userID, _, _, _, let turnEnd) = decodedUser
    else {
        Issue.record("旧版の JSON を読めない")
        return
    }
    #expect((id, text, output) == ("c1", "ls", "a"))
    #expect(completedAt == nil)
    #expect(intent == nil)
    #expect(changeID == "f1")
    #expect(changeCompletedAt == nil)
    #expect(userID == "u1")
    #expect(turnEnd == nil)
}

@Test func newFieldsAreNotWrittenWhenAbsentSoOlderAppsSeeTheSameJSON() throws {
    let item = ChatItem.commandExecution(id: "c1", command: "ls", output: "a", timestamp: started)

    let json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))

    #expect(!json.contains("completedAt"))
    #expect(!json.contains("intent"))
}

// MARK: - 等価性（新フィールドだけが違う 2 つは等しくない）

@Test func commandExecutionsDifferingOnlyInCompletedAtAreNotEqual() {
    let running = ChatItem.commandExecution(id: "c", command: "ls", output: "a", timestamp: started)
    let done = ChatItem.commandExecution(id: "c", command: "ls", output: "a", timestamp: started, completedAt: finished)

    #expect(running != done)
}

@Test func commandExecutionsDifferingOnlyInIntentAreNotEqual() {
    let plain = ChatItem.commandExecution(id: "c", command: "ls", output: "a", timestamp: started)
    let described = ChatItem.commandExecution(id: "c", command: "ls", output: "a", timestamp: started, intent: "一覧を見る")

    #expect(plain != described)
}

@Test func fileChangesDifferingOnlyInCompletedAtAreNotEqual() {
    let running = ChatItem.fileChange(id: "f", changes: [patch()], timestamp: started)
    let done = ChatItem.fileChange(id: "f", changes: [patch()], timestamp: started, completedAt: finished)

    #expect(running != done)
}

@Test func userMessagesDifferingOnlyInTurnEndAreNotEqual() {
    let open = ChatItem.userMessage(id: "u", text: "t", timestamp: started, attachments: [])
    let closed = ChatItem.userMessage(
        id: "u", text: "t", timestamp: started, attachments: [],
        turnEnd: ChatTurnEnd(outcome: .completed, at: finished)
    )
    let interrupted = ChatItem.userMessage(
        id: "u", text: "t", timestamp: started, attachments: [],
        turnEnd: ChatTurnEnd(outcome: .interrupted, at: finished)
    )

    #expect(open != closed)
    #expect(closed != interrupted)
}

@Test func withTimestampKeepsTheNewFields() {
    let item = ChatItem.commandExecution(
        id: "c", command: "ls", output: "a", timestamp: started, completedAt: finished, intent: "一覧を見る"
    )

    #expect(item.withTimestamp(.distantFuture) == item)
}

// MARK: - モバイル向け差分取得の署名

private func expectSignatureChanges(_ before: ChatItem, _ after: ChatItem) {
    #expect(
        TranscriptDeltaCursor.hash([before]) != TranscriptDeltaCursor.hash([after]),
        "差分取得の署名が変わらないと、モバイルは更新を拾えない: \(before)"
    )
}

@Test func transcriptSignatureChangesWhenCommandCompletedAtIsAdded() {
    expectSignatureChanges(
        .commandExecution(id: "c", command: "ls", output: "a", timestamp: started),
        .commandExecution(id: "c", command: "ls", output: "a", timestamp: started, completedAt: finished)
    )
}

@Test func transcriptSignatureChangesWhenCommandIntentIsAdded() {
    expectSignatureChanges(
        .commandExecution(id: "c", command: "ls", output: "a", timestamp: started),
        .commandExecution(id: "c", command: "ls", output: "a", timestamp: started, intent: "一覧を見る")
    )
}

@Test func transcriptSignatureChangesWhenFileChangeCompletedAtIsAdded() {
    expectSignatureChanges(
        .fileChange(id: "f", changes: [patch()], timestamp: started),
        .fileChange(id: "f", changes: [patch()], timestamp: started, completedAt: finished)
    )
}

@Test func transcriptSignatureChangesWhenTurnEndIsAdded() {
    expectSignatureChanges(
        .userMessage(id: "u", text: "t", timestamp: started, attachments: []),
        .userMessage(
            id: "u", text: "t", timestamp: started, attachments: [],
            turnEnd: ChatTurnEnd(outcome: .error, at: finished)
        )
    )
}

@Test func transcriptSignatureSeparatesAnOutcomeChangeFromATimeChange() {
    func closed(_ outcome: ChatTurnEnd.Outcome, at date: Date) -> ChatItem {
        .userMessage(
            id: "u", text: "t", timestamp: started, attachments: [],
            turnEnd: ChatTurnEnd(outcome: outcome, at: date)
        )
    }

    #expect(TranscriptDeltaCursor.hash([closed(.completed, at: finished)]) != TranscriptDeltaCursor.hash([closed(.interrupted, at: finished)]))
    #expect(TranscriptDeltaCursor.hash([closed(.completed, at: finished)]) != TranscriptDeltaCursor.hash([closed(.completed, at: started)]))
}
