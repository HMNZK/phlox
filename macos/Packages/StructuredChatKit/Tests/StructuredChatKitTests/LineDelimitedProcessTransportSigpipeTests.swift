import Foundation
import Testing
@testable import StructuredChatKit

/// 子の標準入力への書き込みは、読み手を失ってもSIGPIPE（既定ではプロセス終了）でなくEPIPEで失敗する。
/// 失敗するのは本体プロセスが落ちること（このテストプロセスごと終了）で、通れば合格。

@Test func writingToAChildThatClosedItsStdinFailsWithoutRaisingSIGPIPE() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh", arguments: ["-c", "exec 0<&-; echo ready; exec sleep 30"])
    try transport.start()
    var lines = transport.receivedLines.makeAsyncIterator()
    // 子が標準入力を閉じたことを確認する。
    #expect(await lines.next().map { String(decoding: $0, as: UTF8.self) } == "ready")

    // 並走する spawn が読み端を exec まで一時継承し得るので、EPIPE になるまで短く再試行する。
    let input = Data("x\n".utf8)
    await #expect(throws: LineDelimitedProcessTransportError.stdinClosed) {
        for _ in 0..<200 {
            try await transport.send(input)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    await transport.close()
}

@Test func aWriteBlockedOnAFullPipeFailsWhenTheChildDiesWithoutRaisingSIGPIPE() async throws {
    // 子は標準入力を読まないので、大きな書き込みはパイプが満杯になってブロックする。
    let transport = LineDelimitedProcessTransport(command: "/bin/sh", arguments: ["-c", "exec sleep 30"])
    try transport.start()
    let write = Task { try await transport.send(Data(repeating: 0x61, count: 4 * 1024 * 1024)) }
    try await Task.sleep(for: .milliseconds(300))

    // 子を終了させると、ブロック中の書き込みは読み手を失う。
    await transport.close()
    let result = await write.result

    if case .success = result { Issue.record("書き込みが成功した（想定外）") }
}
