import Foundation
import StructuredChatKit

public protocol AppServerTransport: Sendable {
    var receivedLines: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
    /// プロセスが自分で終了したときの終了コード（シグナル終了は 128 + シグナル番号）。動作中・未起動は nil。
    func terminationStatus() async -> Int32?
}

public extension AppServerTransport {
    func terminationStatus() async -> Int32? {
        nil
    }
}

/// Codex app-server も Claude と同じ行区切りトランスポートで動かす（ADR 0220）。
extension LineDelimitedProcessTransport: AppServerTransport {}
