import Foundation
import Testing
import StructuredChatKit

// task-20 受け入れテスト（PM 著・実装役は編集禁止）。
// 契約: LineDelimitedProcessTransport は子プロセスの stderr を連続 drain し、
// receivedLines ストリームが終了した時点で `stderrTail()` が末尾（上限 64KiB）を返す。

@Test func stderrTailCapturesProcessStderrAfterStreamEnds() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "echo out1; echo boom1 1>&2; echo boom2 1>&2; exit 1"]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["out1"])
    let tail = try #require(await transport.stderrTail())
    #expect(tail.contains("boom1"))
    #expect(tail.contains("boom2"))
}

@Test func stderrTailIsNilWhenProcessWritesNoStderr() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "echo only-stdout; exit 0"]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["only-stdout"])
    let tail = await transport.stderrTail()
    #expect(tail == nil || tail?.isEmpty == true)
}

// stderr がパイプ容量（64KiB）を大きく超えても子プロセスが書き込みブロックで
// ハングしないこと（連続 drain の検証。このテストがハングする＝drain されていない）。
// tail は上限 64KiB に丸められ、末尾側（最新）が残ること。
@Test func stderrTailIsBoundedAndLargeStderrDoesNotDeadlock() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh",
        arguments: [
            "-c",
            "i=0; while [ $i -lt 4000 ]; do echo 'stderr-filler-line-0123456789-0123456789-0123456789' 1>&2; i=$((i+1)); done; echo MARKER-END 1>&2; echo done",
        ]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["done"])
    let tail = try #require(await transport.stderrTail())
    #expect(tail.contains("MARKER-END"))
    #expect(tail.utf8.count <= 64 * 1024)
}
