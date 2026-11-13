import Foundation

/// 計画的なホスト更新のためにクライアントが返す、確定点の内容（ADR 0233）。
public struct HandoverPreparation: Sendable {
    public let holder: HolderRecord
    /// クライアントが反映済みの最後の受信番号。
    public let appliedSeq: UInt64
    /// エージェント別のクライアント状態（JSON）。
    public let clientState: Data
    /// `events`へ流したフェンスのID。このIDのイベントを受け取り側が処理し終えた時点で、`appliedSeq`までの全イベントが反映済み。
    public let fence: UUID

    public init(holder: HolderRecord, appliedSeq: UInt64, clientState: Data, fence: UUID) {
        self.holder = holder
        self.appliedSeq = appliedSeq
        self.clientState = clientState
        self.fence = fence
    }
}

public enum HandoverError: Error, Equatable, LocalizedError, Sendable {
    /// 更新に対応しない（holderを使わない・未対応の状態）。何も変えていない。
    case notReady(String)
    /// 期限内に確定点を作れなかった。送受信を再開済み。
    case timedOut
    /// 採用できない。子は終了・再生成していない（復旧待ちで残す）。
    case adoptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let reason): "更新できる状態ではありません: \(reason)"
        case .timedOut: "更新の確定点を期限内に作れませんでした。"
        case .adoptionFailed(let reason): "実行の引き継ぎに失敗しました（子は終了していません）: \(reason)"
        }
    }
}

/// 引き継ぎの対象かどうか。
public enum HandoverParticipation: Sendable, Equatable {
    /// 引き継ぎの対象（生きている子を持つ、または判定できない）。
    case participant
    /// 子は既に終了している（例: 中断でCLIが終わった）。引き継ぐ実行が無いので、確定点にも延期理由にも載せない。
    /// 新ホストが通常の復元（再開）で戻す。
    case childEnded
}

/// holder経由で動き、計画的なホスト更新で子を止めずに引き継げるクライアント。
public protocol HandoverCapableClient: StructuredAgentClient {
    /// 更新できない理由。nilなら可。PTY・非holder・応答待ちの操作・結果不明の送信があるときは理由を返す。
    func handoverGateReason() async -> String?
    /// 新しい送信を止め、受信を止め、状態を確定し、`events`へフェンスを流す。失敗時は送受信を再開してから投げる。
    func prepareHandover(fence: UUID) async throws -> HandoverPreparation
    /// 確定に成功しなかったとき、送受信を再開する。
    func cancelHandover() async
    /// 不可逆の確定点。holderの保持を確定済み番号まで破棄させ、書込権を手放す。子もholderも終了しない。
    func commitHandover(confirmedThrough: UInt64) async
    /// 引き継ぎ側: 状態を復元し、未回答の要求を再投入して、受信を始める（新しい子は作らない）。
    func completeAdoption() async throws
    /// 子が既に終了しているか。終了していれば引き継ぎの対象外（既定は対象）。
    func handoverParticipation() async -> HandoverParticipation
}

public extension HandoverCapableClient {
    func handoverParticipation() async -> HandoverParticipation { .participant }
}

/// 計画的なホスト更新の間、新しいセッションの起動を止める門（ADR 0233）。更新を始める側が閉じ、失敗時に開く。
public final class HandoverGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    public init() {}

    /// holderを起動している最中の件数。閉鎖後に始まる起動は無いので、0になれば確定点から漏れる起動は無い。
    private var launching = 0

    public var isClosed: Bool { lock.withLock { closed } }
    public var launchingCount: Int { lock.withLock { launching } }
    public func close() { lock.withLock { closed = true } }
    public func open() { lock.withLock { closed = false } }

    /// holderを起動する入口。閉じていれば偽（起動しない）。真なら、起動が終わったら必ず`endLaunch()`を呼ぶ。
    public func beginLaunch() -> Bool {
        lock.withLock {
            guard !closed else { return false }
            launching += 1
            return true
        }
    }

    public func endLaunch() { lock.withLock { launching = max(0, launching - 1) } }

    /// 閉じて、閉じる前に始まった起動が終わるのを待つ。期限までに終わらなければ偽（更新を中止する。門は閉じたまま）。
    public func closeAndDrain(timeout: Duration = .seconds(20)) async -> Bool {
        close()
        let deadline = ContinuousClock.now + timeout
        while launchingCount > 0 {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
