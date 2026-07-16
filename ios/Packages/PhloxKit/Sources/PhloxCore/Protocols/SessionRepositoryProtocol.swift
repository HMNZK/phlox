import Foundation

/// セッション一覧の購読口（DI シーム / E3-5）。
///
/// ポーリングを `AsyncStream<SessionsState>` で抽象化し、ViewModel はポーリング実装を意識しない。
/// P2 では APNs プッシュ駆動の別実装へ差し替え可能（architecture.md / board P2-APNs）。
public protocol SessionRepositoryProtocol: Sendable {
    /// `interval` 間隔でポーリングし、状態変化を配信する。購読開始時に `.loading` を流す。
    func sessionStream(interval: Duration) -> AsyncStream<SessionsState>
    /// 即時 1 回の再取得（プル更新など）。
    func refresh() async throws
}

public extension SessionRepositoryProtocol {
    /// 既定間隔（3 秒）のストリーム。
    func sessionStream() -> AsyncStream<SessionsState> {
        sessionStream(interval: .seconds(3))
    }
}
