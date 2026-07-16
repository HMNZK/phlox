import Foundation
import Testing
import AgentDomain
import PTYKit
import TerminalUI
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - 実 Claude Code の入力準備完了(wait-ready)E2E テスト(env gate / アプリ起動なし)
//
// 目的: 「isReadyForInput(viaHook) が true になった時点で、実際に Claude Code の TUI が
// 入力を受理する」ことを実 CLI で証明する。初回 PTY 出力だけで ready 扱いにすると
// TUI 起動完了前に書き込んだ入力が破棄される(再現済みバグ)ため、SessionStart フック受信 +
// 出力静止(settle)を ready 条件とした修正の妥当性を実測で裏づける。
//
// 実フックの発火タイミングは、SessionStart フックにマーカーファイル書き出しコマンドを
// 仕込み、マーカー出現を検出した瞬間にテスト所有の hookEvents stream へ .sessionStart を
// yield することで VM に正確に反映する(HookServer 不要)。
//
// 前提: claude がインストール済みかつログイン済み。未インストールなら自動スキップ。
// 実行: PHLOX_E2E=1 swift test --filter RealClaudeReadinessE2E

// ヘルパ(isE2EEnabled / resolveBinary / childEnvironment / makeTempWorkingDirectory / waitUntil)は
// E2ETestSupport.swift の共有定義を使う。

@Suite("E2E RealClaudeReadiness")
struct RealClaudeReadinessE2ETests {

    @Test(.enabled(if: isE2EEnabled() && resolveBinary("claude") != nil), .timeLimit(.minutes(2)))
    @MainActor
    func realClaude_inputAcceptedAfterSessionStartHook() async throws {
        let claude = try #require(resolveBinary("claude"))
        let workDir = makeTempWorkingDirectory()
        let markerPath = (workDir as NSString).appendingPathComponent("sessionstart.marker")

        // SessionStart フックでマーカーファイルを書き出す最小 settings JSON。
        let settings: [String: Any] = [
            "hooks": [
                "SessionStart": [[
                    "matcher": "",
                    "hooks": [["type": "command", "command": "touch '\(markerPath)'"]],
                ]],
            ],
        ]
        let settingsPath = (workDir as NSString).appendingPathComponent("settings.json")
        let settingsData = try JSONSerialization.data(withJSONObject: settings)
        try settingsData.write(to: URL(fileURLWithPath: settingsPath))

        let sessionID = SessionID()
        let pty = PTYManager()
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let spawnRequest = SessionViewModel.SpawnRequest(
            command: claude,
            args: ["--settings", settingsPath],
            env: childEnvironment(),
            workingDirectory: workDir,
            kind: .claudeCode,
            statusBootstrap: .viaHook
        )
        let vm = SessionViewModel(
            id: sessionID,
            ptyManager: pty,
            hookEvents: hookStream,
            terminalCoordinator: TerminalCoordinator(),
            spawnRequest: spawnRequest
        )

        await vm.start()
        vm.terminalCoordinator.onResize(100, 30)

        // 実フック発火(マーカー出現)を検出した瞬間に .sessionStart を VM へ届ける。
        let markerDetected = await waitUntil(timeoutNanoseconds: 60_000_000_000) {
            FileManager.default.fileExists(atPath: markerPath)
        }
        let sessionStartAt = Date()
        guard markerDetected else {
            // trust プロンプト等で SessionStart まで到達しない環境では実証不能なためスキップ扱い。
            let screen = vm.terminalCoordinator.visibleText()
            print("[RealClaudeReadinessE2E] SessionStart マーカー未検出のためスキップ。画面:\n\(screen)")
            await vm.kill()
            await pty.terminateAllAndWait(timeout: .seconds(5))
            return
        }
        hookContinuation.yield((sessionID, .sessionStart))

        // 新判定(SessionStart + settle)で ready へ到達する。
        let ready = await waitUntil(timeoutNanoseconds: 30_000_000_000) { vm.isReadyForInput }
        let readyAt = Date()
        #expect(ready, "SessionStart 受信 + 出力静止後も isReadyForInput が true にならなかった")

        // ready 時点で入力が実際に受理される(エコーバックが画面に現れる)ことを証明する。
        await vm.sendInput(Data("PHLOXPROBE".utf8))
        let echoed = await waitUntil(timeoutNanoseconds: 10_000_000_000) {
            vm.terminalCoordinator.visibleText().contains("PHLOXPROBE")
        }
        print("[RealClaudeReadinessE2E] SessionStart→ready: "
            + String(format: "%.2f", readyAt.timeIntervalSince(sessionStartAt)) + "s, echoed=\(echoed)")
        #expect(echoed, "ready 判定後に書き込んだ入力が TUI にエコーバックされなかった(まだ早すぎる)")

        await vm.kill()
        await pty.terminateAllAndWait(timeout: .seconds(5))
    }
}
