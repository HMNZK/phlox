import AgentDomain
import Foundation
import os

public final class StreamCache: Sendable {
    private let outputLock = OSAllocatedUnfairLock(initialState: [SessionID: AsyncStream<Data>]())
    private let exitLock = OSAllocatedUnfairLock(initialState: [SessionID: AsyncStream<Int32>]())

    public init() {}

    public func register(
        id: SessionID,
        output: AsyncStream<Data>,
        exit: AsyncStream<Int32>
    ) {
        outputLock.withLock { $0[id] = output }
        exitLock.withLock { $0[id] = exit }
    }

    public func outputStream(for id: SessionID) -> AsyncStream<Data>? {
        outputLock.withLock { $0[id] }
    }

    public func exitStream(for id: SessionID) -> AsyncStream<Int32>? {
        exitLock.withLock { $0[id] }
    }

    /// セッション終了時に両ストリームのエントリを削除する。
    /// 削除後の lookup は nil を返す（PTYManager 側では即 finish する空 stream にフォールバックする）。
    public func remove(id: SessionID) {
        outputLock.withLock { $0[id] = nil }
        exitLock.withLock { $0[id] = nil }
    }
}
