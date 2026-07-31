import AppKit
import DashboardFeature

/// AppDelegate の終了処理を、アプリ層から明示的に呼べる形で分離する。
/// 実際の終了待機は `applicationShouldTerminate` でこのメソッドを起動する。
@MainActor
extension AppDelegate {
    func shutdownUserTerminal() async {
        await userTerminalController?.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // シグナル経路と同じガードで「高々 1 回」を担保する。シグナル側が先行済みなら、
        // ここでは子終了を再実行せず終了する。
        guard cleanupGuard.beginCleanup() else { return .terminateNow }

        let ptyManager = self.ptyManager
        let dashboard = self.dashboard
        Task { @MainActor in
            // ユーザーターミナルの明示 shutdown と既存 PTY 終了、transcript flush を待つ。
            let ptyTask = Task {
                await self.shutdownUserTerminal()
                guard let ptyManager else { return }
                await ptyManager.terminateAllAndWait(timeout: Self.cleanupTimeout)
            }
            let flushTask = Task { @MainActor in
                await Self.flushChatTranscriptsForTermination(
                    dashboard: dashboard,
                    timeout: Self.transcriptFlushTimeout
                )
            }
            await ptyTask.value
            await flushTask.value
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
