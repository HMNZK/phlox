import Foundation
import Testing
import AgentDomain
import PTYKit
import TerminalUI
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - 実 PTY ヘッドレス統合テスト（env gate / アプリ起動なし）
//
// 目的: mock では検証できない「実プロセスの起動→ready 検知→実出力回収→400ms settle で
// idle 完了検知」を、SessionViewModel + 実 PTYManager の通し経路で確かめる。GUI も `/Applications`
// への配置も不要で、テストは一時ディレクトリで動くため本番 Phlox データ(`Application Support/Phlox`)
// を汚さない。
//
// 通常の `swift test` / CI からは除外する(実 CLI・タイミング依存・Ollama 前提のため)。
// 実行は次のように env gate を立てる:
//   PHLOX_E2E=1 swift test --filter E2E
//
// - `realPTY_deterministic_...`  : 外部依存なし(/bin/sh)。idle-fallback 機構そのものを決定論的に検証。

// MARK: - Tests

@Suite("E2E RealPTY")
struct E2ERealPTYTests {

    /// 決定論的な実 PTY 検証: /bin/sh で「起動時に ready 出力 → 入力をエコー → 沈黙」を再現し、
    /// SessionViewModel + 実 PTYManager の idle-fallback 経路が end-to-end で動くことを確かめる。
    /// 外部 CLI に依存しないため、env gate さえ立てれば確実に再現する(機構の安定版)。
    @Test(.enabled(if: isE2EEnabled()), .timeLimit(.minutes(1)))
    @MainActor
    func realPTY_deterministic_inputEchoThenSilenceReachesIdleCompletion() async {
        let sessionID = SessionID()
        let pty = PTYManager()
        let script = "printf 'ready\\n'; while IFS= read -r line; do printf 'you said: %s\\n' \"$line\"; done"
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: "/bin/sh",
            args: ["-c", script],
            env: childEnvironment(),
            workingDirectory: makeTempWorkingDirectory(),
            kind: .cursor,
            statusBootstrap: .idleOnSpawnComplete
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: pty,
            hookEvents: AsyncStream { _ in },
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )

        await vm.start()
        vm.terminalCoordinator.onResize(80, 24)

        // 起動出力("ready") + settle で ready(.idle) になる
        let ready = await waitUntil(timeoutNanoseconds: 10_000_000_000) { vm.status == .idle }
        #expect(ready, "実 PTY 起動後に ready(.idle) へ到達しなかった")

        // 送信 → エコー出力 → 沈黙 → 400ms settle で完了検知
        vm.markInputSubmitted()
        #expect(vm.status == .running)
        await vm.sendInput(Data("hello\n".utf8))

        let completed = await waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.status == .idle && vm.hasUnseenCompletion
        }
        #expect(completed, "出力沈黙後に idle 完了検知が発火しなかった")

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }

}
