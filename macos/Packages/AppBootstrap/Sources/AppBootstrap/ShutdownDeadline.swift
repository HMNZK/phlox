import Foundation

/// 停止要求から一定時間で必ずプロセスを終えるための期限。
/// 期限は指定キューで発火し、MainActor や停止処理本体が戻らなくても exit に到達する。
/// 正常な停止経路が先に exit すればこの期限は何も起こさない（取消しは不要）。
public final class ShutdownDeadline: Sendable {
    private let timeout: Duration
    private let queue: DispatchQueue
    private let exit: @Sendable (Int32) -> Void
    private let once = CleanupGuard()

    public init(timeout: Duration, queue: DispatchQueue, exit: @escaping @Sendable (Int32) -> Void) {
        self.timeout = timeout
        self.queue = queue
        self.exit = exit
    }

    /// 期限を張る。2 回目以降は無視する（最初の exitCode が使われる）。
    public func arm(exitCode: Int32) {
        guard once.beginCleanup() else { return }
        let milliseconds = Int(timeout / .milliseconds(1))
        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [exit] in exit(exitCode) }
    }
}
