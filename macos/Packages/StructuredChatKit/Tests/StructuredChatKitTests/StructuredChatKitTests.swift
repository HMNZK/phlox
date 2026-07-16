import Foundation
import Testing
@testable import StructuredChatKit

@Test func lineDelimitedTransportSplitsStdoutIntoLinesAndFlushesFinalPartialLine() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "printf 'one\\ntwo\\npartial'"]
    )
    try transport.start()

    var iterator = transport.receivedLines.makeAsyncIterator()
    let first = await iterator.next()
    let second = await iterator.next()
    let third = await iterator.next()

    #expect(first.map { String(data: $0, encoding: .utf8) } == "one")
    #expect(second.map { String(data: $0, encoding: .utf8) } == "two")
    #expect(third.map { String(data: $0, encoding: .utf8) } == "partial")
    await transport.close()
}

@Test func lineDelimitedTransportInterruptSendsSIGINTWithoutClosingStdout() async throws {
    let transport = LineDelimitedProcessTransport(
        command: "/usr/bin/perl",
        arguments: [
            "-e",
            "$|=1; $SIG{INT}=sub { print \"interrupted\\n\"; }; print \"ready\\n\"; while (1) { select undef, undef, undef, 0.1 }",
        ]
    )
    try transport.start()

    var iterator = transport.receivedLines.makeAsyncIterator()
    let first = await iterator.next()
    await transport.interrupt()
    let second = await iterator.next()

    #expect(first.map { String(data: $0, encoding: .utf8) } == "ready")
    #expect(second.map { String(data: $0, encoding: .utf8) } == "interrupted")
    await transport.close()
}

@Test func oneShotProcessRunnerCollectsLineDelimitedOutputAndExitCode() async throws {
    let runner = OneShotProcessRunner()
    let result = try await runner.run(
        command: "/bin/sh",
        arguments: ["-c", "printf 'alpha\\nbeta\\n'; exit 7"]
    )

    #expect(result.exitCode == 7)
    #expect(result.outputLines.map { String(data: $0, encoding: .utf8) } == ["alpha", "beta"])
}

@Test func oneShotProcessRunnerCollectsLineDelimitedStderrAndExitCode() async throws {
    let runner = OneShotProcessRunner()
    let result = try await runner.run(
        command: "/bin/sh",
        arguments: ["-c", "printf 'alpha\\nbeta\\n'; printf 'err-one\\nerr-two\\n' >&2; exit 7"]
    )

    #expect(result.exitCode == 7)
    #expect(result.outputLines.map { String(data: $0, encoding: .utf8) } == ["alpha", "beta"])
    #expect(result.errorLines.map { String(data: $0, encoding: .utf8) } == ["err-one", "err-two"])
}

@Test func oneShotProcessRunnerDrainsLargeStdoutWhileProcessRuns() async throws {
    let runner = OneShotProcessRunner()
    let result = try await runner.run(
        command: "/usr/bin/perl",
        arguments: ["-e", "for ($i = 0; $i < 4096; $i++) { print 'x' x 64, \"\\n\" }"]
    )

    #expect(result.exitCode == 0)
    #expect(result.outputLines.count == 4096)
    #expect(result.outputLines.reduce(0) { $0 + $1.count } > 128 * 1024)
}

@Test func oneShotProcessRunnerDrainsLargeStderrWhileProcessRuns() async throws {
    let runner = OneShotProcessRunner()
    let result = try await runner.run(
        command: "/usr/bin/perl",
        arguments: ["-e", "for ($i = 0; $i < 4096; $i++) { print STDERR 'e' x 64, \"\\n\" }"]
    )

    #expect(result.exitCode == 0)
    #expect(result.errorLines.count == 4096)
    #expect(result.errorLines.reduce(0) { $0 + $1.count } > 128 * 1024)
}

@Test func oneShotProcessRunnerPreservesLineContentAndOrderUnderHeavyOutput() async throws {
    let runner = OneShotProcessRunner()
    let lineCount = 20_000

    for iteration in 0..<50 {
        let result = try await runner.run(
            command: "/usr/bin/perl",
            arguments: ["-e", "for ($i = 0; $i < \(lineCount); $i++) { print \"line$i\\n\" }"]
        )

        #expect(result.exitCode == 0)
        #expect(result.outputLines.count == lineCount, "iteration \(iteration)")
        for index in 0..<lineCount {
            let line = String(data: result.outputLines[index], encoding: .utf8)
            #expect(line == "line\(index)", "iteration \(iteration), line \(index)")
        }
    }
}

@Test func oneShotProcessRunnerRetainsFinalLineEmittedNearTermination() async throws {
    let runner = OneShotProcessRunner()
    let result = try await runner.run(
        command: "/usr/bin/perl",
        arguments: [
            "-e",
            "for ($i = 0; $i < 8192; $i++) { print 'line', $i, \"\\n\" } print \"TERMINATION_MARKER\\n\"",
        ]
    )

    #expect(result.exitCode == 0)
    #expect(result.outputLines.count == 8193)
    #expect(result.outputLines.last.map { String(data: $0, encoding: .utf8) } == "TERMINATION_MARKER")
}
