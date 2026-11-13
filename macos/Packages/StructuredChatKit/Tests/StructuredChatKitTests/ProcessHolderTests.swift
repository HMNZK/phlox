import Darwin
import Foundation
import Testing
@testable import StructuredChatKit

/// holder境界（ADR 0233）の契約テスト。実際の子プロセス（/bin/cat・/bin/sh）とUnixソケットで確かめる。
/// ソケットパスの長さ制限のため、短い一時ディレクトリを使う。
private struct HolderFixture {
    let holder: ProcessHolder
    let record: HolderRecord
    let root: String

    /// ソケットのパス長の上限（104バイト）のため、worktree配下でなく短い一時ディレクトリを使う。自分で作り、`cleanUp`で消す。
    static func newRoot() -> String { "/tmp/phx-" + UUID().uuidString.prefix(8).lowercased() }

    init(
        root: String = HolderFixture.newRoot(), command: String = "/bin/cat", arguments: [String] = [],
        retentionLimit: Int = HolderProtocol.defaultRetentionLimit
    ) throws {
        self.root = root
        let spec = HolderSpawnSpec(
            command: command, arguments: arguments, environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil, metadata: ["session": "test"],
            recordDirectory: root + "/r", socketDirectory: root + "/s", retentionLimit: retentionLimit)
        holder = ProcessHolder(spec: spec, orphanLinger: 5)
        record = try holder.start()
    }

    func transport(from seq: UInt64 = 0) throws -> HolderTransport {
        let transport = HolderTransport(source: .adopt(record: record, fromSeq: seq))
        try transport.start()
        return transport
    }

    /// 子はsh -cの最後を`exec`にする（孫が残らず、`kill`1回で子が全て終わる）。
    func cleanUp() {
        kill(record.childPID, SIGKILL)
        try? FileManager.default.removeItem(atPath: root)
    }
}

/// 時間切れで失敗する行読み取り。ハングをテストの失敗として表す。
private final class LineReader: @unchecked Sendable {
    private var iterator: AsyncStream<Data>.Iterator
    init(_ transport: HolderTransport) { iterator = transport.receivedLines.makeAsyncIterator() }

    func next(timeout: Duration = .seconds(10)) async -> String? {
        await withTaskGroup(of: String??.self) { group in
            group.addTask { [self] in .some(await iterator.next().map { String(decoding: $0, as: UTF8.self) }) }
            group.addTask { try? await Task.sleep(for: timeout); return .none }
            let first = await group.next() ?? .none
            group.cancelAll()
            return first ?? nil
        }
    }
}

private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

@Test func holderDeliversChildOutputInOrderWithSequenceNumbers() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let transport = try fixture.transport()
    let reader = LineReader(transport)

    for text in ["a", "b", "c"] { try await transport.send(line(text)) }

    #expect(await reader.next() == "a")
    #expect(await reader.next() == "b")
    #expect(await reader.next() == "c")
    #expect(transport.processIdentifier == fixture.record.childPID)
}

@Test func newAttachTakesWriteAuthorityAndOldWriterIsRejected() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let old = try fixture.transport()
    let oldReader = LineReader(old)
    try await old.send(line("before"))
    #expect(await oldReader.next() == "before")

    let new = try fixture.transport(from: 1)
    try await new.send(line("after"))

    // 古い接続は書込権を失い、書込は拒否される（子には届かない）。
    await #expect(throws: HolderError.self) { try await old.send(line("stale")) }
    let newReader = LineReader(new)
    #expect(await newReader.next() == "after")
    #expect(new.attachInfo?.epoch ?? 0 > old.attachInfo?.epoch ?? 0)
    #expect(new.processIdentifier == old.processIdentifier)
}

@Test func adoptReplaysOnlyLinesAfterTheCommittedSequence() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let first = try fixture.transport()
    let firstReader = LineReader(first)
    for text in ["one", "two", "three"] { try await first.send(line(text)) }
    for _ in 0..<3 { _ = await firstReader.next() }

    // 2行目まで反映済みとして引き継ぐ。3行目だけが再送される。
    let second = try fixture.transport(from: 2)
    let secondReader = LineReader(second)
    #expect(await secondReader.next() == "three")
}

@Test func detachForHandoverKeepsTheSameChildRunning() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let old = try fixture.transport()
    let oldReader = LineReader(old)
    try await old.send(line("working"))
    #expect(await oldReader.next() == "working")
    // 本番の受信ループと同じく、消費側は次の行を要求して待機している。
    let parked = Task { await oldReader.next(timeout: .seconds(30)) }
    defer { parked.cancel() }
    try await Task.sleep(for: .milliseconds(100))
    let applied = try #require(await old.quiesce())
    old.confirm(through: applied)
    old.releaseForHandover()

    let new = try fixture.transport(from: applied)
    try await new.send(line("continued"))
    let newReader = LineReader(new)

    #expect(await newReader.next() == "continued")
    #expect(new.processIdentifier == fixture.record.childPID)
    #expect(kill(fixture.record.childPID, 0) == 0)
}

@Test func resendingTheSameSendIDDoesNotWriteTwice() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let client = try HolderClient.connect(socketPath: fixture.record.socketPath, fromSeq: 0)
    let pump = HolderLinePump(startSeq: 0) { _ in }
    client.startReader(onLine: { pump.push(seq: $0, data: $1) }, onExited: { _, _ in }, onEnd: { _ in })
    let epoch = client.attach.epoch
    let sendID = UUID()

    let first = try await client.request { .write(epoch: epoch, requestID: $0, sendID: sendID, data: line("once")) }
    let second = try await client.request { .write(epoch: epoch, requestID: $0, sendID: sendID, data: line("once")) }
    _ = try await client.request { .write(epoch: epoch, requestID: $0, sendID: UUID(), data: line("marker")) }

    #expect(first == .written)
    #expect(second == .written)
    // catの出力は「once」が1回だけで、次が「marker」。
    #expect(String(decoding: await pump.next() ?? Data(), as: UTF8.self) == "once")
    #expect(String(decoding: await pump.next() ?? Data(), as: UTF8.self) == "marker")
    client.disconnect()
}

@Test func retentionLimitStopsReadingInsteadOfDroppingUnconfirmedOutput() async throws {
    // 1行41バイト前後 × 50行 = 約2KB。上限400バイトなので、確認が進まない間は読み取りを止める。
    let fixture = try HolderFixture(
        command: "/bin/sh",
        arguments: ["-c", "i=0; while [ $i -lt 50 ]; do printf 'line-%02d-0123456789012345678901234567\\n' $i; i=$((i+1)); done; exec sleep 30"],
        retentionLimit: 400)
    defer { fixture.cleanUp() }
    // 確認を返さない接続で、保持量が上限に達するまで待つ。
    let client = try HolderClient.connect(socketPath: fixture.record.socketPath, fromSeq: 0)
    let stalled = HolderLinePump(startSeq: 0) { _ in }
    client.startReader(onLine: { stalled.push(seq: $0, data: $1) }, onExited: { _, _ in }, onEnd: { _ in })
    try await Task.sleep(for: .milliseconds(800))

    let probe = try fixture.transport()
    let info = try #require(probe.attachInfo)
    #expect(info.backpressured)
    #expect(info.firstRetainedSeq == 1) // 確認前の行は1行も捨てていない
    probe.releaseForHandover()
    client.disconnect()

    // 確認を進めながら読むと、全50行が欠けず順に届く。
    let transport = try fixture.transport()
    let reader = LineReader(transport)
    for index in 0..<50 {
        let text = try #require(await reader.next())
        #expect(text.hasPrefix(String(format: "line-%02d-", index)))
    }
}

/// 接続の確立直後に手放す（読み取りスレッドが動き出す前に閉じる）ことを繰り返しても、
/// 空いたfd番号の再利用で後続の握手が横取り・誤書込みされない。以前は並走で握手が期限切れ/即切断になった。
@Test func rapidReleaseAndReattachNeverBreaksALaterHandshake() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    for _ in 0..<60 {
        let transport = try fixture.transport()
        transport.releaseForHandover()
    }
    let last = try fixture.transport()
    let reader = LineReader(last)
    try await last.send(line("still reachable"))
    #expect(await reader.next() == "still reachable")
}

@Test func exitStatusIsReportedAndStreamEndsAfterAllLines() async throws {
    let fixture = try HolderFixture(command: "/bin/sh", arguments: ["-c", "echo done; exit 3"])
    defer { fixture.cleanUp() }
    let transport = try fixture.transport()
    let reader = LineReader(transport)

    #expect(await reader.next() == "done")
    #expect(await reader.next() == nil)
    #expect(await transport.terminationStatus() == 3)
}

@Test func quiesceReturnsLastProcessedSequenceAndHoldsLaterLines() async throws {
    // 子が自分で後続の出力を作る（旗のファイルを待ってから「y」を出す）。更新中は送信を拒否するので、
    // 「更新中も子の出力は保持され、渡されない」ことは子の自発的な出力で確かめる。
    let root = HolderFixture.newRoot()
    let flag = root + "/go"
    let fixture = try HolderFixture(
        root: root, command: "/bin/sh",
        arguments: ["-c", "echo x; while [ ! -e '\(flag)' ]; do sleep 0.05; done; echo y; exec sleep 30"])
    defer { fixture.cleanUp() }
    let transport = try fixture.transport()
    let reader = LineReader(transport)
    #expect(await reader.next() == "x")

    // 消費側が次を要求して待機しているので、処理済み=1。
    let delivered = LostBox()
    let reachedNext = Task {
        let value = await reader.next(timeout: .seconds(20))
        delivered.ended = true
        return value
    }
    try await Task.sleep(for: .milliseconds(100))
    let applied = try #require(await transport.quiesce())
    FileManager.default.createFile(atPath: flag, contents: Data())
    try await Task.sleep(for: .milliseconds(500)) // 「y」が出力され、holderから届くのに十分な時間

    #expect(applied == 1)
    // 停止中は「y」を渡さない（処理済みを超えない）。再開すると届く。
    #expect(delivered.ended == false)
    transport.resumeAfterQuiesce()
    #expect(await reachedNext.value == "y")
}

@Test func quiesceGivesUpWhenTheConsumerNeverFinishesTheLastLine() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let transport = try fixture.transport()
    let reader = LineReader(transport)
    try await transport.send(line("busy"))
    #expect(await reader.next() == "busy")
    // 消費側が次を要求しない（処理が終わらない）。待ち続けず、nilで返って送信を再開する。

    let applied = await transport.quiesce(timeout: .milliseconds(300))

    #expect(applied == nil)
    try await transport.send(line("still works"))
}

@Test func sendIsRejectedWhileQuiescedAndNothingIsWritten() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let transport = try fixture.transport()
    let reader = LineReader(transport)
    let parked = Task { await reader.next(timeout: .seconds(30)) }
    defer { parked.cancel() }
    try await Task.sleep(for: .milliseconds(100))
    _ = try #require(await transport.quiesce())

    await #expect(throws: HolderError.handoverInProgress) { try await transport.send(line("late")) }

    transport.resumeAfterQuiesce()
    try await transport.send(line("after"))
    // 更新中に拒否した「late」は子に届かず、再開後の「after」だけが出力される。
    #expect(await parked.value == "after")
}

@Test func evictedConnectionIsReportedAsOwnershipLossNotAsChildExit() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let old = try fixture.transport()
    let lost = LostBox()
    old.setOwnershipLossHandler { lost.reason = $0 }
    let streamEnded = LostBox()
    Task { for await _ in old.receivedLines {}; streamEnded.ended = true }

    let new = try fixture.transport()
    try await Task.sleep(for: .milliseconds(400))

    #expect(lost.reason == .evicted)
    // 子は生きていて、古い側の受信は終端されない（終了と誤認して起動し直さない）。
    #expect(kill(fixture.record.childPID, 0) == 0)
    #expect(streamEnded.ended == false)
    #expect(await old.terminationStatus() == nil)
    _ = new
}

@Test func closeTerminatesTheChildEndsTheStreamAndLetsTheHolderFinish() async throws {
    let fixture = try HolderFixture()
    let transport = try fixture.transport()
    let reader = LineReader(transport)

    await transport.close()

    #expect(await reader.next() == nil)
    // 終了を待って確認まで返すので、holderは記録を消して終わる。
    try await Task.sleep(for: .milliseconds(500))
    #expect(kill(fixture.record.childPID, 0) != 0)
    #expect(HolderCatalog.records(in: fixture.root + "/r").isEmpty)
    try? FileManager.default.removeItem(atPath: fixture.root)
}

private final class LostBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HolderTransport.EndReason?
    private var didEnd = false
    var reason: HolderTransport.EndReason? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    var ended: Bool {
        get { lock.withLock { didEnd } }
        set { lock.withLock { didEnd = newValue } }
    }
}

/// 子の1行は最大64MiB（`LineDelimitedProcessTransport`の上限）。JSONの`Data`はbase64で4/3に膨らむので、
/// 上限ぎりぎりの行もフレームとして符号化できなければならない（符号化に失敗したフレームは黙って捨てられ、行が失われる）。
@Test func frameLimitAdmitsALineAtTheMaximumLineSize() throws {
    let maximumLine = 64 * 1024 * 1024
    let frame = try HolderWire.encode(HolderFrame.line(seq: 1, data: Data(count: maximumLine)))
    #expect(frame.count - 4 <= HolderProtocol.maximumFrameBytes)
    // 受け取る側（HolderClient）も同じ上限で読む。
    let request = try HolderWire.encode(HolderRequest.write(epoch: 1, requestID: 1, sendID: UUID(), data: Data(count: maximumLine)))
    #expect(request.count - 4 <= HolderProtocol.maximumFrameBytes)
}

/// 旧ホストが反映した番号より後の行がholderから既に破棄されているなら、引き継ぐと受信を取りこぼす。
/// 採用側は、番号の連続性を検査して断る（確認（confirm）は送らず、手放すだけ）。
@Test func adoptionIsRefusedWhenLinesAfterTheAppliedSequenceWereAlreadyDiscarded() async throws {
    let fixture = try HolderFixture(command: "/bin/sh", arguments: ["-c", "printf 'a\\nb\\nc\\nd\\ne\\n'; exec sleep 30"])
    defer { fixture.cleanUp() }
    // 5行（seq 1〜5）を受け、seq 5まで確認する（holderは破棄する）。
    let first = try fixture.transport()
    let reader = LineReader(first)
    for _ in 0..<5 { #expect(await reader.next() != nil) }
    first.confirm(through: 5)
    // 同じ接続の要求は順に処理されるので、この返事が来た時点で確認は反映済み。
    _ = await first.stderrTail()
    first.releaseForHandover()

    // 反映済みの番号が2（3〜5が必要）のまま採用しようとすると、欠落として断る。
    let stale = try fixture.transport(from: 2)
    let fault = try #require(stale.adoptionContinuityFault(), "破棄済みの行に気づかず引き継げてしまう")
    #expect(fault.contains("保持する行が足りません"))
    stale.releaseForHandover()

    // 断った採用は確認を送らない（holderの状態は変わらず、子も生きている）。
    let again = try fixture.transport(from: 5)
    #expect(again.adoptionContinuityFault() == nil)
    #expect(again.attachInfo?.lastSeq == 5)
    #expect(again.attachInfo?.firstRetainedSeq == 6)
    #expect(kill(fixture.record.childPID, 0) == 0)
    again.releaseForHandover()
}

@Test func adoptionIsRefusedWhenTheHolderIsBehindTheAppliedSequence() async throws {
    let fixture = try HolderFixture()
    defer { fixture.cleanUp() }
    let transport = try fixture.transport(from: 9)
    #expect(transport.adoptionContinuityFault()?.contains("より小さい") == true)
    transport.releaseForHandover()
}

/// base64は`/`を含む。既定のJSONエンコーダは`/`を`\/`にエスケープするので、0xFFの列（base64が`/`ばかり）は
/// 4/3でなく8/3に膨らむ。最悪ケースでも、上限ぎりぎりの行が符号化できなければならない（黙って捨てられない）。
@Test func frameLimitAdmitsAWorstCaseLineWhoseBase64IsAllSlashes() throws {
    let maximumLine = 64 * 1024 * 1024
    let frame = try HolderWire.encode(HolderFrame.line(seq: 1, data: Data(repeating: 0xFF, count: maximumLine)))
    #expect(frame.count - 4 <= HolderProtocol.maximumFrameBytes)
    // 往復しても同じ行になる（エスケープしない形でも正しく読める）。
    let small = Data(repeating: 0xFF, count: 1024)
    let encoded = try HolderWire.encode(HolderFrame.line(seq: 7, data: small))
    let decoded = try JSONDecoder().decode(HolderFrame.self, from: encoded.dropFirst(4))
    if case .line(let seq, let data) = decoded { #expect(seq == 7 && data == small) } else { Issue.record("行でない") }
}
