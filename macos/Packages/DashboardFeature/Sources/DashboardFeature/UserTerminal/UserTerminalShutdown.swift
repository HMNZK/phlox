/// アプリ終了時のユーザーターミナルの後始末。共通ターミナルとセッションごとのシェルを、孤児プロセスを残さないよう明示的に止める。
@MainActor
public func shutdownUserTerminals(common: UserTerminalController?, sessions: SessionTerminalStore?) async {
    await common?.shutdown()
    await sessions?.shutdownAll()
}
