import AgentDomain
import Foundation
import Testing
@testable import PTYKit

// C-6: ターミナルを閉じる前の確認は、シェルに子プロセス（動いているコマンド）があるときだけ出す。

@Test func hasChildProcesses_isTrueOnlyWhileACommandRuns() async throws {
    let manager = PTYManager()
    let id = try await manager.spawn(command: "/bin/sh", args: [], env: ["PATH": "/usr/bin:/bin"])
    #expect(await manager.hasChildProcesses(id) == false)

    try await manager.write(Data("sleep 5\n".utf8), to: id)
    var running = false
    for _ in 0..<50 where !running {
        try await Task.sleep(for: .milliseconds(100))
        running = await manager.hasChildProcesses(id)
    }
    #expect(running)

    await manager.hangUp(id)
}

// シェルが `exec` でコマンドに置き換わっても「動いている」とみなす。
@Test func hasChildProcesses_isTrueWhenTheShellExecsACommand() async throws {
    let manager = PTYManager()
    let id = try await manager.spawn(command: "/bin/sh", args: [], env: ["PATH": "/usr/bin:/bin"])
    #expect(await manager.hasChildProcesses(id) == false)
    try await manager.write(Data("exec sleep 5\n".utf8), to: id)
    var running = false
    for _ in 0..<50 where !running {
        try await Task.sleep(for: .milliseconds(100))
        running = await manager.hasChildProcesses(id)
    }
    #expect(running)
    await manager.hangUp(id)
}

// C-42 / 02「ターミナルのタブを閉じるとシェルを終了する」: 対話シェルは SIGTERM を無視するので SIGHUP で終える。
@Test func hangUp_endsAnInteractiveShell() async throws {
    let manager = PTYManager()
    let id = try await manager.spawn(command: "/bin/zsh", args: ["-f", "-i"], env: ["PATH": "/usr/bin:/bin"])
    let exits = manager.exitStream(for: id)
    await manager.hangUp(id)
    let exited = Task { for await _ in exits { return true }; return false }
    let timeout = Task { try await Task.sleep(for: .seconds(5)); exited.cancel() }
    #expect(await exited.value)
    timeout.cancel()
}
