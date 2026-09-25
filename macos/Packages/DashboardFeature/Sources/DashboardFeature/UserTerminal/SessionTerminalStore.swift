import Foundation
import AgentDomain

/// セッションごとのターミナルタブのシェル（02 C「ターミナル（この worktree で）」）。
/// タブを切り替えても・セッションを切り替えても残し、タブを閉じたときとアプリ終了時にだけ止める。
/// 表示の途中で作ってよいよう、観測対象にはしない（中身の表示は各 `TerminalPanelSession` が持つ）。
@MainActor
public final class SessionTerminalStore {
    /// 作業ディレクトリを受け取ってシェルを作る。PTY・シェル・環境変数は App が決める。
    public typealias Factory = @MainActor (_ workingDirectory: String) -> TerminalPanelSession

    private var terminals: [SessionID: (session: TerminalPanelSession, workingDirectory: String)] = [:]
    private let factory: Factory

    public init(factory: @escaping Factory) {
        self.factory = factory
    }

    /// 初めて開くときだけ作る。シェルの起動は表示時（`TerminalPanelView.task`）まで遅らせる。
    /// セッションの作業場所が変わっていたら、旧い場所のシェルを止めて新しい場所で作り直す。
    public func terminal(for sessionID: SessionID, workingDirectory: String) -> TerminalPanelSession {
        if let existing = terminals[sessionID] {
            if existing.workingDirectory == workingDirectory { return existing.session }
            close(sessionID)
        }
        let created = factory(workingDirectory)
        terminals[sessionID] = (created, workingDirectory)
        return created
    }

    /// 開いていれば、そのセッションのターミナル（作らない）。
    public func existing(_ sessionID: SessionID) -> TerminalPanelSession? {
        terminals[sessionID]?.session
    }

    /// シェルが動いているか（閉じる前の確認に使う）。
    public func isRunning(_ sessionID: SessionID) -> Bool {
        terminals[sessionID]?.session.controller.isRunning ?? false
    }

    /// シェルの中でコマンドが動いているか。
    public func hasRunningCommand(_ sessionID: SessionID) async -> Bool {
        await terminals[sessionID]?.session.controller.hasRunningCommand() ?? false
    }

    /// タブを閉じた・セッションを削除したときにシェルを止める。置き場からはすぐ外すので、
    /// 停止を待つあいだに開き直しても新しいシェルになる（旧いシェルの停止が新しい表示を止めない）。
    @discardableResult
    public func close(_ sessionID: SessionID) -> Task<Void, Never>? {
        guard let terminal = terminals.removeValue(forKey: sessionID)?.session else { return nil }
        return Task { await terminal.controller.shutdown() }
    }

    /// アプリ終了時。
    public func shutdownAll() async {
        let all = terminals.values.map(\.session)
        terminals.removeAll()
        for terminal in all {
            await terminal.controller.shutdown()
        }
    }
}
