// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — パネル用ユーザーターミナルの中核（PTY ライフサイクル）。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面:
// - UserTerminalController(pty:shellPath:workingDirectory:environment:)
// - isRunning / sessionID / ensureStarted() / send(_:) / makeOutputStream() / shutdown()
//
// ゲート①決定: シェルはセッション（エージェント）と無関係の独立プロセス。
// パネル UI の開閉と無関係に生き続け、アプリ終了時にのみ shutdown される。

import Foundation
import PTYKit
import Testing
@testable import DashboardFeature

@Suite("User terminal acceptance (task-1)", .timeLimit(.minutes(1)))
@MainActor
struct AcceptanceUserTerminalTests {

    private func makeController(
        pty: PTYManager,
        home: URL
    ) -> UserTerminalController {
        UserTerminalController(
            pty: pty,
            shellPath: "/bin/sh",
            workingDirectory: home.path,
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": home.path,
                "TERM": "dumb",
            ]
        )
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-terminal-acceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 条件が真になるまでポーリングで待つ（固定 sleep 単発ではなく期限付きループ）。
    private func waitUntil(
        timeoutSeconds: Double = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "タイムアウト: 条件が \(timeoutSeconds) 秒以内に成立しなかった")
    }

    @Test("ensureStarted はシェルを起動し、コマンドの出力がストリームへ流れる")
    func startAndEcho() async throws {
        let home = try makeTempHome()
        let controller = makeController(pty: PTYManager(), home: home)

        try await controller.ensureStarted()
        #expect(controller.isRunning == true)
        _ = try #require(controller.sessionID)

        let stream = controller.makeOutputStream()
        let collector = OutputCollector()
        let consumeTask = Task {
            for await chunk in stream {
                await collector.append(chunk)
            }
        }
        defer { consumeTask.cancel() }

        // 入力エコーと区別するため、出力にだけ現れる文字列を組み立てて検証する。
        try await controller.send("printf 'phlox_%s\\n' acceptance_marker\n")
        try await waitUntilAsync { await collector.text().contains("phlox_acceptance_marker") }

        await controller.shutdown()
    }

    @Test("ensureStarted は冪等: 起動済みなら sessionID が変わらない")
    func ensureStartedIsIdempotent() async throws {
        let home = try makeTempHome()
        let controller = makeController(pty: PTYManager(), home: home)

        try await controller.ensureStarted()
        let first = try #require(controller.sessionID)
        try await controller.ensureStarted()
        let second = try #require(controller.sessionID)
        #expect(first == second)

        await controller.shutdown()
    }

    @Test("シェルが自然終了すると isRunning が false になり、再度 ensureStarted で新プロセスが立つ")
    func naturalExitAllowsRestart() async throws {
        let home = try makeTempHome()
        let controller = makeController(pty: PTYManager(), home: home)

        try await controller.ensureStarted()
        let first = try #require(controller.sessionID)

        try await controller.send("exit\n")
        try await waitUntil { controller.isRunning == false }

        try await controller.ensureStarted()
        #expect(controller.isRunning == true)
        let second = try #require(controller.sessionID)
        #expect(first != second)

        await controller.shutdown()
    }

    @Test("shutdown はプロセスを終了させ、冪等に呼べる")
    func shutdownStopsAndIsIdempotent() async throws {
        let home = try makeTempHome()
        let controller = makeController(pty: PTYManager(), home: home)

        try await controller.ensureStarted()
        await controller.shutdown()
        try await waitUntil { controller.isRunning == false }

        // 終了済み・未起動状態で呼んでもクラッシュ・ハングしない。
        await controller.shutdown()
        #expect(controller.isRunning == false)
    }

    // MARK: - harness

    /// actor ベースの出力収集（テスト間共有なし）。
    private actor OutputCollector {
        private var buffer = Data()
        func append(_ data: Data) { buffer.append(data) }
        func text() -> String { String(decoding: buffer, as: UTF8.self) }
    }

    private func waitUntilAsync(
        timeoutSeconds: Double = 10,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let finalResult = await condition()
        #expect(finalResult, "タイムアウト: 条件が \(timeoutSeconds) 秒以内に成立しなかった")
    }
}
