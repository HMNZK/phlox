import Foundation
import Testing
@testable import StructuredChatKit

private struct MockLineDelimitedTransport: LineDelimitedTransport {
    var receivedLines: AsyncStream<Data> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async {}
}

@Test func lineDelimitedTransportDefaultStderrTailIsNil() async {
    let transport = MockLineDelimitedTransport()

    let tail = await transport.stderrTail()

    #expect(tail == nil)
}

@Test func processTransportCapturesStderrWithoutRequiringTrailingNewline() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "printf 'stdout-line\\n'; printf 'stderr-partial' >&2"]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["stdout-line"])
    #expect(await transport.stderrTail() == "stderr-partial")
}

@Test func processTransportStderrTailKeepsOnlyNewest64KiB() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/usr/bin/perl",
        arguments: [
            "-e",
            "print STDERR \"OLD_MARKER\\n\"; print STDERR \"x\" x 70000; print STDERR \"NEW_MARKER\\n\"; print \"done\\n\";",
        ]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    let tail = try #require(await transport.stderrTail())
    #expect(lines == ["done"])
    #expect(tail.contains("NEW_MARKER"))
    #expect(!tail.contains("OLD_MARKER"))
    #expect(tail.utf8.count <= 64 * 1024)
}

// 04 B3: プロセスが自分で終わったら、行の流れが閉じる前に終了コードを記録している。
@Test func processTransportRecordsTheExitCodeBeforeTheLinesFinish() async throws {
    let transport = LineDelimitedProcessTransport(command: "/bin/sh", arguments: ["-c", "printf 'x\\n'; exit 3"])
    #expect(await transport.terminationStatus() == nil)
    try transport.start()
    for await _ in transport.receivedLines {}
    #expect(await transport.terminationStatus() == 3)
}

@Test func processTransportReportsASignalExitAs128PlusTheSignal() async throws {
    let transport = LineDelimitedProcessTransport(command: "/bin/sh", arguments: ["-c", "kill -TERM $$"])
    try transport.start()
    for await _ in transport.receivedLines {}
    #expect(await transport.terminationStatus() == 128 + SIGTERM)
}

// 子が複数行を書いて即終了しても、両方の読み取りの EOF を待って finish するので最終行を取りこぼさない。
@Test func processTransportDeliversFinalLineBeforeFinishAcrossRepeatedRuns() async throws {
    for _ in 0..<20 {
        let transport = LineDelimitedProcessTransport(
            command: "/bin/sh",
            arguments: ["-c", "printf '{\"id\":1}\\n{\"id\":2}\\n{\"id\":\"FINAL\"}\\n'"]
        )
        try transport.start()

        var lines: [String] = []
        for await line in transport.receivedLines {
            lines.append(String(data: line, encoding: .utf8) ?? "")
        }

        #expect(lines == ["{\"id\":1}", "{\"id\":2}", "{\"id\":\"FINAL\"}"])
    }
}

// ADR 0220: 改行の来ない行が上限を超えたら、理由を stderr 末尾に残して子を止める。
@Test(.timeLimit(.minutes(1)))
func processTransportStopsTheChildWhenALineExceedsTheLimit() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/usr/bin/perl",
        arguments: ["-e", "$|=1; print \"ok\\n\"; print \"x\" x 2048; print STDERR \"e\" x 70000; sleep 30;"],
        maxLineBytes: 1024
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["ok"])
    #expect(await transport.terminationStatus() == 128 + SIGKILL)
    #expect(try #require(await transport.stderrTail()).contains("exceeded 1024 bytes"))
}
