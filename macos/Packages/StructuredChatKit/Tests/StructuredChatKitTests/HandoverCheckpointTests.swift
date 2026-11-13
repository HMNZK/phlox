import Darwin
import Foundation
import Testing
@testable import StructuredChatKit

/// チェックポイント（ADR 0233）の保存・読み出しの契約。採用の安全性（所有者・モード・版）をここで固定する。
private struct CheckpointFixture {
    let root: URL
    var directory: URL { root.appendingPathComponent("handover", isDirectory: true) }

    init() {
        root = URL(fileURLWithPath: "/tmp/phx-ck-" + UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    static func sample(applied: UInt64 = 7) -> HandoverCheckpoint {
        let holder = HolderRecord(
            holderID: "h-test", protocolVersion: 1, holderPID: 11, childPID: 22,
            socketPath: "/tmp/phx-x/s/h-test.sock", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            metadata: ["session": "S1", "agent": "claudeCode"])
        return HandoverCheckpoint(
            createdAt: Date(timeIntervalSince1970: 1_800_000_100), sourceGeneration: "G1", hookPort: 41_001, controlPort: 41_002,
            sessions: [HandoverSession(sessionID: "S1", agent: "claudeCode", holder: holder, appliedSeq: applied, clientState: Data("state".utf8),
                                      token: "secret-S1")])
    }
}

@Test func checkpointRoundTripsEveryField() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    let original = CheckpointFixture.sample()

    try HandoverCheckpointStore.write(original, directory: fixture.directory)
    let read = try #require(try HandoverCheckpointStore.read(directory: fixture.directory))

    #expect(read == original)
    #expect(read.sessions.first?.holder.socketPath == "/tmp/phx-x/s/h-test.sock")
    #expect(read.sessions.first?.appliedSeq == 7)
    #expect(read.sessions.first?.token == "secret-S1")
    var info = stat()
    #expect(stat(HandoverCheckpointStore.checkpointURL(directory: fixture.directory).path, &info) == 0)
    #expect(info.st_mode & 0o777 == 0o600)
}

@Test func missingCheckpointIsNilNotAnError() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == nil)
}

@Test func writeReplacesAtomicallyAndLeavesNoTemporaryFile() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    try HandoverCheckpointStore.write(CheckpointFixture.sample(applied: 1), directory: fixture.directory)
    try HandoverCheckpointStore.write(CheckpointFixture.sample(applied: 2), directory: fixture.directory)

    let read = try #require(try HandoverCheckpointStore.read(directory: fixture.directory))
    #expect(read.sessions.first?.appliedSeq == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["checkpoint.json"])
}

@Test func checkpointWithWrongModeOrSymlinkOrUnknownFormatIsRejected() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    try HandoverCheckpointStore.write(CheckpointFixture.sample(), directory: fixture.directory)
    let file = HandoverCheckpointStore.checkpointURL(directory: fixture.directory)

    chmod(file.path, 0o644)
    #expect(throws: HandoverCheckpointError.self) { try HandoverCheckpointStore.read(directory: fixture.directory) }
    chmod(file.path, 0o600)

    // 形式の版が違うものは採用しない。
    var future = CheckpointFixture.sample()
    future.formatVersion = 99
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(future).write(to: file)
    chmod(file.path, 0o600)
    #expect(throws: HandoverCheckpointError.unsupportedFormat(99)) { try HandoverCheckpointStore.read(directory: fixture.directory) }

    // シンボリックリンクは辿らない。
    let real = fixture.directory.appendingPathComponent("real.json")
    try FileManager.default.moveItem(at: file, to: real)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: real)
    #expect(throws: HandoverCheckpointError.self) { try HandoverCheckpointStore.read(directory: fixture.directory) }
}

@Test func consumedCheckpointIsNotReadAgain() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    try HandoverCheckpointStore.write(CheckpointFixture.sample(), directory: fixture.directory)

    try HandoverCheckpointStore.markConsumed(directory: fixture.directory)

    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == nil)
}

private func twoSessionCheckpoint() -> HandoverCheckpoint {
    var checkpoint = CheckpointFixture.sample()
    var second = checkpoint.sessions[0]
    second.sessionID = "S2"
    second.appliedSeq = 9
    checkpoint.sessions.append(second)
    return checkpoint
}

@Test func consumingOnlyAdoptedSessionsKeepsTheFailedOnesForRetry() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    let original = twoSessionCheckpoint()
    try HandoverCheckpointStore.write(original, directory: fixture.directory)

    // S1は採用成功。S2は失敗・不明なので残す。
    try HandoverCheckpointStore.consume(sessionIDs: ["S1"], directory: fixture.directory)

    let remaining = try #require(try HandoverCheckpointStore.read(directory: fixture.directory))
    #expect(remaining.sessions.map(\.sessionID) == ["S2"])
    #expect(remaining.sessions.first?.appliedSeq == 9)
    // ポート・世代・形式は変わらない（残った子は同じポートを環境変数に固定している）。
    #expect(remaining.hookPort == original.hookPort)
    #expect(remaining.controlPort == original.controlPort)
    #expect(remaining.sourceGeneration == original.sourceGeneration)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["checkpoint.json"])
}

@Test func checkpointIsConsumedOnlyWhenEveryItemIsAdoptedOrAbandoned() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    try HandoverCheckpointStore.write(twoSessionCheckpoint(), directory: fixture.directory)

    try HandoverCheckpointStore.consume(sessionIDs: ["S1"], directory: fixture.directory)
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) != nil)

    // 残りの項目を放棄（または採用成功）した時点で全体が消費済みになる。
    try HandoverCheckpointStore.consume(sessionIDs: ["S2"], directory: fixture.directory)
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == nil)
}

@Test func consumingWithNoMatchingSessionLeavesTheCheckpointUntouched() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    let original = twoSessionCheckpoint()
    try HandoverCheckpointStore.write(original, directory: fixture.directory)

    // 採用に1件も成功しなかった（空集合）・未知のIDでは、何も外さない。
    try HandoverCheckpointStore.consume(sessionIDs: [], directory: fixture.directory)
    try HandoverCheckpointStore.consume(sessionIDs: ["unknown"], directory: fixture.directory)

    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == original)
}

@Test func discardRemovesOnlyACheckpointWrittenByTheSameGeneration() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    try HandoverCheckpointStore.write(CheckpointFixture.sample(), directory: fixture.directory)

    // 他の世代が書いたものには触れない。
    #expect(try HandoverCheckpointStore.discard(sourceGeneration: "other", directory: fixture.directory) == false)
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) != nil)

    // 自分の世代のものは消える。次のホスト起動は何も採用しない。
    #expect(try HandoverCheckpointStore.discard(sourceGeneration: "G1", directory: fixture.directory) == true)
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == nil)
}

@Test func discardWithoutACheckpointDoesNothing() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    #expect(try HandoverCheckpointStore.discard(sourceGeneration: "G1", directory: fixture.directory) == false)
}

/// 子の認証トークンは、採用し終えたら確定点の記録に残さない。採用に失敗した項目は再試行のために保つ。
@Test func consumingRemovesTokensOnlyOnceEveryItemIsAdopted() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    var checkpoint = twoSessionCheckpoint()
    checkpoint.sessions[1].token = "secret-S2"
    try HandoverCheckpointStore.write(checkpoint, directory: fixture.directory)

    try HandoverCheckpointStore.consume(sessionIDs: ["S1"], directory: fixture.directory)
    let remaining = try #require(try HandoverCheckpointStore.read(directory: fixture.directory))
    #expect(remaining.sessions.map(\.token) == ["secret-S2"])

    try HandoverCheckpointStore.consume(sessionIDs: ["S2"], directory: fixture.directory)
    #expect(try HandoverCheckpointStore.read(directory: fixture.directory) == nil)
    let consumed = try String(contentsOf: fixture.directory.appendingPathComponent("consumed.json"), encoding: .utf8)
    #expect(consumed.contains("S2"))
    #expect(!consumed.contains("secret-S"), "消費済みの記録にトークンが残っている")
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["consumed.json"])
}

/// トークンの無い確定点（この項目より前の形式）も読める。新ホストは新しいトークンを発行する。
@Test func checkpointWithoutTokenIsStillReadable() throws {
    let fixture = CheckpointFixture()
    defer { fixture.cleanUp() }
    var legacy = CheckpointFixture.sample()
    legacy.sessions[0].token = nil
    try HandoverCheckpointStore.write(legacy, directory: fixture.directory)
    let raw = try String(contentsOf: HandoverCheckpointStore.checkpointURL(directory: fixture.directory), encoding: .utf8)
    #expect(!raw.contains("\"token\""))

    let read = try #require(try HandoverCheckpointStore.read(directory: fixture.directory))
    #expect(read.sessions.first?.token == nil)
    #expect(read.sessions.first?.sessionID == "S1")
}
