import Foundation
import AgentDomain
import Observation

/// プロジェクトのターミナルタブごとのシェル。
/// タブを切り替えても・セッションを切り替えても残し、タブを閉じたときとアプリ終了時にだけ止める。
/// 子タブの置き場は観測対象外。下部の置き場だけを観測し、初回表示の task で作る。
@MainActor
@Observable
public final class ProjectTerminalStore {
    /// 作業ディレクトリを受け取ってシェルを作る。PTY・シェル・環境変数は App が決める。
    public typealias Factory = @MainActor (_ workingDirectory: String) -> TerminalPanelSession

    @ObservationIgnored private var terminals: [TerminalTabID: (session: TerminalPanelSession, projectID: ProjectID, workingDirectory: String)] = [:]
    @ObservationIgnored private let factory: Factory
    private var bottomTerminals: [ProjectID: (session: TerminalPanelSession, workingDirectory: String)] = [:]
    public func bottomTerminal(for projectID: ProjectID, workingDirectory: String) -> TerminalPanelSession {
        if let existing = bottomTerminals[projectID] {
            if existing.workingDirectory == workingDirectory { return existing.session }
            bottomTerminals.removeValue(forKey: projectID)
            Task { await existing.session.controller.shutdown() }
        }
        let session = factory(workingDirectory)
        bottomTerminals[projectID] = (session, workingDirectory)
        return session
    }

    public func existingBottomTerminal(for projectID: ProjectID) -> TerminalPanelSession? {
        bottomTerminals[projectID]?.session
    }

    public func canRestartBottomTerminal(for projectID: ProjectID?) -> Bool {
        guard let projectID else { return false }
        return bottomTerminals[projectID]?.session.controller.hasStarted == true
    }

    public init(factory: @escaping Factory) {
        self.factory = factory
    }

    /// 初めて開くときだけ作る。シェルの起動は表示時（`TerminalPanelView.task`）まで遅らせる。
    /// プロジェクトのフォルダが変わっていたら、旧い場所のシェルを止めて新しい場所で作り直す。
    public func terminal(for tabID: TerminalTabID, projectID: ProjectID, workingDirectory: String) -> TerminalPanelSession {
        if let existing = terminals[tabID] {
            if existing.projectID == projectID && existing.workingDirectory == workingDirectory { return existing.session }
            close(tabID)
        }
        let created = factory(workingDirectory)
        terminals[tabID] = (created, projectID, workingDirectory)
        return created
    }

    /// 開いていれば、そのタブのターミナル（作らない）。
    public func existing(_ tabID: TerminalTabID) -> TerminalPanelSession? {
        terminals[tabID]?.session
    }

    /// シェルが動いているか（閉じる前の確認に使う）。
    public func isRunning(_ tabID: TerminalTabID) -> Bool {
        terminals[tabID]?.session.controller.isRunning ?? false
    }

    /// シェルの中でコマンドが動いているか。
    public func hasRunningCommand(_ tabID: TerminalTabID) async -> Bool {
        await terminals[tabID]?.session.controller.hasRunningCommand() ?? false
    }

    /// タブを閉じた・プロジェクトを削除したときにシェルを止める。置き場からはすぐ外すので、
    /// 停止を待つあいだに開き直しても新しいシェルになる（旧いシェルの停止が新しい表示を止めない）。
    @discardableResult
    public func close(_ tabID: TerminalTabID) -> Task<Void, Never>? {
        guard let terminal = terminals.removeValue(forKey: tabID)?.session else { return nil }
        return Task { await terminal.controller.shutdown() }
    }

    public func closeProject(_ projectID: ProjectID) async {
        let bottom = bottomTerminals.removeValue(forKey: projectID)?.session
        let ids = terminals.filter { $0.value.projectID == projectID }.map(\.key)
        let tasks = ids.compactMap { close($0) }
        for task in tasks { await task.value }
        await bottom?.controller.shutdown()
    }

    /// アプリ終了時。
    public func shutdownAll() async {
        let all = terminals.values.map(\.session) + bottomTerminals.values.map(\.session)
        terminals.removeAll()
        bottomTerminals.removeAll()
        for terminal in all {
            await terminal.controller.shutdown()
        }
    }
}
