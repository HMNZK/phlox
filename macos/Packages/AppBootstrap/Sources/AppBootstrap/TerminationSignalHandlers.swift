import Foundation

/// 終了シグナルを指定キューで監視する DispatchSource を設置する。
public enum TerminationSignalHandlers {
    /// 各シグナルの既定動作を SIG_IGN で無効化してから DispatchSource を設置し resume する。
    /// handler は @Sendable のため、呼び出し元の actor isolation を継承せず指定キューで直接実行される。
    /// 返り値の source は呼び出し側が保持する。
    public static func install(
        signals: [Int32],
        queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) -> [DispatchSourceSignal] {
        signals.map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            return source
        }
    }
}
