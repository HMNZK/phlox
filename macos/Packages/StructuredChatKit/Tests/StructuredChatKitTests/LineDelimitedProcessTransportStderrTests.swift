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
