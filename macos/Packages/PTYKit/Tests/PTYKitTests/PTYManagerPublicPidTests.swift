import AgentDomain
import Foundation
import Testing
// 注: 他の PTYKit テストと異なり、ここはあえて `@testable` を付けない。
// `pid(for:)` が module 外（App/環境層）から到達可能な public であることを、
// 通常 import 経由でのコンパイル可否そのもので検証するため。internal に戻ると
// このファイルがコンパイルできず red になる。
import PTYKit

private let publicPidTestEnv: [String: String] = [
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
]

// MARK: - pid アクセサの公開（App/環境層から到達できること）

@Test func spawnedSession_exposesChildPidThroughPublicAccessor() async throws {
    let manager = PTYManager()
    let id = try await manager.spawn(
        command: "/bin/sleep",
        args: ["30"],
        env: publicPidTestEnv
    )
    defer { Task { await manager.kill(id) } }

    let pid = try #require(await manager.pid(for: id))
    #expect(pid > 0)
    #expect(Posix.isAlive(pid: pid))
}

@Test func unknownSession_returnsNilFromPublicPidAccessor() async {
    let manager = PTYManager()
    let pid = await manager.pid(for: SessionID())
    #expect(pid == nil)
}
