import Foundation

/// 終了時クリーンアップ（子セッションの一括終了）を「高々 1 回」だけ起動するためのガード。
///
/// SIGTERM / SIGINT のシグナルハンドラと、GUI の正常終了経路
/// （`applicationShouldTerminate`）の双方からクリーンアップが要求されうる。
/// どちらが先に走っても、また同一経路が二重に呼ばれても、実際のクリーンアップは 1 回だけにしたい。
///
/// `beginCleanup()` を返す `Bool` で「自分がクリーンアップの起動権を取れたか」を表す。
/// 起動権を取れたのは最初の 1 回だけで、以降は `false` を返す。
/// 並行アクセス（シグナルハンドラの DispatchQueue と MainActor など）に備え、
/// フラグの判定と更新は `NSLock` で直列化する。
///
/// 注意: SIGKILL（kill -9）やハードクラッシュはプロセス内で捕捉できないため、
/// このガードでは扱えない（取りこぼしは起動時 reap でカバーする）。
public final class CleanupGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasStarted = false

    public init() {}

    /// クリーンアップの起動権を要求する。
    ///
    /// - Returns: 自分が最初の呼び出しなら `true`（呼び出し側はクリーンアップを実行してよい）。
    ///   既に他の呼び出しが起動権を取得済みなら `false`（呼び出し側はクリーンアップをスキップする）。
    public func beginCleanup() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasStarted {
            return false
        }
        hasStarted = true
        return true
    }

    /// 既にクリーンアップが起動されているか（主にテスト・観測用）。
    public var hasBegun: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasStarted
    }

    /// クリーンアップ起動権を取れたときだけ `body` を実行する。
    /// 2 回目以降の呼び出しでは `body` は実行されない（idempotent）。
    @discardableResult
    public func runOnce(_ body: () -> Void) -> Bool {
        guard beginCleanup() else { return false }
        body()
        return true
    }
}
