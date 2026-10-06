import Foundation
import Testing
@testable import CodexAppServerKit

// ProcessTransport: 子プロセスの stdout 行の配送・stderr のドレイン・終了コードの記録。

private enum ProcessTransportTestError: Error {
    case timedOut
}

private func collectProcessLines(
    from transport: ProcessTransport,
    timeout: Duration = .seconds(5)
) async throws -> [String] {
    do {
        let lines = try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask {
                var lines: [String] = []
                for await line in transport.receivedLines {
                    lines.append(String(data: line, encoding: .utf8) ?? "")
                }
                return lines
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                await transport.close()
                throw ProcessTransportTestError.timedOut
            }
            defer { group.cancelAll() }
            guard let lines = try await group.next() else {
                throw ProcessTransportTestError.timedOut
            }
            return lines
        }
        await transport.close()
        return lines
    } catch {
        await transport.close()
        throw error
    }
}

@Test(.timeLimit(.minutes(1)))
func processTransportDoesNotHangWhenChildFloodsStderr() async throws {
    // 子が 64KiB を超える stderr を出してから stdout に応答を書く。stderr を並行ドレインしないと、
    // 子は stderr write でブロックし stdout に到達できず、transport は永遠に応答を返さない（hang）。
    let transport = ProcessTransport(
        command: "/usr/bin/perl",
        arguments: [
            "-e",
            "print STDERR \"x\" x 200000; print \"STDOUT_SURVIVED\\n\";",
        ]
    )
    try transport.start()

    let lines = try await collectProcessLines(from: transport)

    #expect(lines == ["STDOUT_SURVIVED"])
}

// 終了直前の応答をドレインしてから finish する（応答喪失なし）

@Test func processTransportDeliversFinalLineBeforeFinishAcrossRepeatedRuns() async throws {
    // 子が複数行を書いて即座に終了する。terminationHandler で即 finish すると、reader が最後の行を
    // 読み切る前にストリームが閉じ、終了直前の応答を取りこぼしうる。両 reader の EOF を待って
    // finish し、残データを読み切ってから閉じれば最終行は必ず届く。
    for _ in 0..<20 {
        let transport = ProcessTransport(
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

@Test func processTransportDeliversTrailingLineWithoutFinalNewline() async throws {
    // 末尾に改行のない最終行も、finish 時の残データ読み切りで喪失しない。
    let transport = ProcessTransport(
        command: "/bin/sh",
        arguments: ["-c", "printf 'line-1\\nline-2-no-newline'"]
    )
    try transport.start()

    var lines: [String] = []
    for await line in transport.receivedLines {
        lines.append(String(data: line, encoding: .utf8) ?? "")
    }

    #expect(lines == ["line-1", "line-2-no-newline"])
}

// app-server が自分で終わったら、行の流れが閉じる前に終了コードを記録している。
@Test func processTransportRecordsTheExitCodeBeforeTheLinesFinish() async throws {
    let transport = ProcessTransport(command: "/bin/sh", arguments: ["-c", "printf '{\"id\":1}\\n'; exit 4"])
    try transport.start()
    for await _ in transport.receivedLines {}
    #expect(await transport.terminationStatus() == 4)
}
