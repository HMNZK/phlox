/// アプリ終了時にプロジェクトのタブで開いたシェルを明示的に止める。
@MainActor
public func shutdownUserTerminals(sessions: ProjectTerminalStore?) async {
    await sessions?.shutdownAll()
}
