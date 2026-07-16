import Foundation
import AgentDomain

public struct PTYInitialSize: Sendable, Equatable {
    public let cols: UInt16
    public let rows: UInt16
    public init(cols: UInt16, rows: UInt16) {
        self.cols = cols
        self.rows = rows
    }
}

public protocol PTYManagerProtocol: Sendable {
    /// 子プロセスを spawn して SessionID を返す。
    /// `id` が nil のときは内部で新規 `SessionID` を生成する。
    /// `initialSize` を渡すと PTY を最初から指定サイズで開く（claude 等 TUI のゴースト描画回避）。
    /// `workingDirectory` を渡すと子プロセスの CWD を明示する（不要な TCC ダイアログ抑止）。
    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID

    /// 指定セッションの stdin にデータを書き込む。
    func write(_ data: Data, to id: SessionID) async throws

    /// セッションを終了させる（SIGTERM）。
    func kill(_ id: SessionID) async

    /// PTY のウィンドウサイズを変更する。`TIOCSWINSZ` を内部で送信する想定。
    /// 既定実装は no-op。具体実装は `PTYManager` 側で行う。
    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws

    /// セッションの stdout/stderr 出力ストリーム。
    func outputStream(for id: SessionID) -> AsyncStream<Data>

    /// セッションの終了コードストリーム（プロセス終了時に 1 要素のみ発行）。
    func exitStream(for id: SessionID) -> AsyncStream<Int32>

    /// PTY master fd の winsize を返す。default 実装は nil (mock 等)。
    /// protocol body に宣言しないと `any PTYManagerProtocol` 経由で extension default が
    /// static dispatch されて実装が呼ばれないため、ここで requirement として明示する。
    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)?
}

public extension PTYManagerProtocol {
    func spawn(command: String, args: [String], env: [String: String]) async throws -> SessionID {
        try await spawn(command: command, args: args, env: env, id: nil, initialSize: nil, workingDirectory: nil)
    }

    func spawn(command: String, args: [String], env: [String: String], id: SessionID?) async throws -> SessionID {
        try await spawn(command: command, args: args, env: env, id: id, initialSize: nil, workingDirectory: nil)
    }

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?
    ) async throws -> SessionID {
        try await spawn(command: command, args: args, env: env, id: id, initialSize: initialSize, workingDirectory: nil)
    }

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        // 既定: 何もしない
    }

    /// PTY master fd の winsize を返す。default は nil (mock や未実装の場合)。
    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        nil
    }
}
