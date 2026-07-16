import Foundation

/// シグナルハンドラ（バックグラウンドキュー）から MainActor を経由せずに値を読み出すための、
/// ロックで保護した nonisolated な箱。
///
/// 背景: 終了時に子セッションを一括終了するには、シグナルハンドラから PTYManager（actor）へ
/// 到達する必要がある。AppDelegate の `ptyManager` は `@MainActor` 隔離プロパティのため、
/// シグナルハンドラから読むと MainActor ホップが必要になる。アプリがハングして MainActor
/// （メインスレッド）がブロック中に SIGTERM/SIGINT が来ると、このホップが永久に進まず、
/// 子終了にも `exit` にも到達できない（デッドロック窓）。
///
/// この箱は `NSLock` で保護した値を nonisolated に保持し、MainActor を一切経由せずに
/// 読み書きできるようにする。格納する値は `Sendable`（actor の参照など）を想定する。
public final class SignalSafeBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        self.storage = value
    }

    /// 現在の値を読み出す（任意のスレッドから安全）。
    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// 値を更新する（任意のスレッドから安全）。
    public func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        storage = newValue
    }
}
