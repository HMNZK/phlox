import Foundation
import Testing
@testable import StructuredChatKit

/// 計画的なホスト更新（ADR 0233）の門。閉じた後に新しいholderを起動してはならず、閉じる前に始まった起動は待てる。

@Test func gateRefusesNewLaunchesOnceClosedAndCountsTheOnesInFlight() {
    let gate = HandoverGate()
    #expect(gate.beginLaunch())
    #expect(gate.launchingCount == 1)
    gate.close()
    #expect(!gate.beginLaunch(), "閉じた後に起動が始まった")
    #expect(gate.launchingCount == 1)
    gate.endLaunch()
    #expect(gate.launchingCount == 0)
    gate.open()
    #expect(gate.beginLaunch())
    gate.endLaunch()
}

@Test func closeAndDrainWaitsForALaunchThatStartedBeforeTheGateClosed() async {
    let gate = HandoverGate()
    #expect(gate.beginLaunch())
    Task {
        try? await Task.sleep(for: .milliseconds(150))
        gate.endLaunch()
    }

    let drained = await gate.closeAndDrain(timeout: .seconds(5))

    #expect(drained)
    #expect(gate.isClosed)
    #expect(gate.launchingCount == 0)
}

@Test func closeAndDrainGivesUpAtTheDeadlineAndKeepsTheGateClosed() async {
    let gate = HandoverGate()
    #expect(gate.beginLaunch())

    let drained = await gate.closeAndDrain(timeout: .milliseconds(100))

    #expect(!drained, "終わらない起動を待ち続けた/終わったことにした")
    #expect(gate.isClosed)
    gate.endLaunch()
}

@Test func holderLaunchIsRefusedWhileTheGateIsClosedWithoutSpawningAnything() throws {
    let gate = HandoverGate()
    gate.close()
    let spec = HolderSpawnSpec(
        command: "/bin/sh", arguments: ["-c", "exec sleep 30"], environment: [:], workingDirectory: nil, metadata: [:],
        recordDirectory: "/tmp/phx-gate-none/r", socketDirectory: "/tmp/phx-gate-none/s")
    // 実行ファイルが存在しなくても、門で断られる（起動を試みれば launchFailed になるはず）。
    let transport = HolderTransport(
        source: .launch(spec: spec, executable: "/nonexistent/phlox"), launchGate: gate)

    #expect(throws: HolderError.handoverInProgress) { try transport.start() }
    #expect(gate.launchingCount == 0)
}

@Test func holderLaunchCountsAsInFlightUntilTheStartReturns() throws {
    let gate = HandoverGate()
    let spec = HolderSpawnSpec(
        command: "/bin/sh", arguments: ["-c", "exec sleep 30"], environment: [:], workingDirectory: nil, metadata: [:],
        recordDirectory: "/tmp/phx-gate-none/r", socketDirectory: "/tmp/phx-gate-none/s")
    let transport = HolderTransport(
        source: .launch(spec: spec, executable: "/nonexistent/phlox"), launchGate: gate)

    // 起動に失敗しても、件数は戻る（門が永久に塞がらない）。
    #expect(throws: (any Error).self) { try transport.start() }
    #expect(gate.launchingCount == 0)
}
