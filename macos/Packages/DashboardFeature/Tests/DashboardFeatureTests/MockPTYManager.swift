import Foundation
import AgentDomain
import PTYKit
import os

struct SpawnCall: Sendable, Equatable {
    let command: String
    let args: [String]
    let env: [String: String]
    let id: SessionID?
    let initialSize: PTYInitialSize?
    let workingDirectory: String?
}

struct ResizeCall: Sendable, Equatable {
    let id: SessionID
    let cols: UInt16
    let rows: UInt16
}

final class MockPTYManager: PTYManagerProtocol, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var spawnSessionID = SessionID()
        var outputStreams: [SessionID: AsyncStream<Data>] = [:]
        var exitStreams: [SessionID: AsyncStream<Int32>] = [:]
        var outputContinuations: [SessionID: AsyncStream<Data>.Continuation] = [:]
        var pendingOutput: [SessionID: [Data]] = [:]
        var exitContinuations: [SessionID: AsyncStream<Int32>.Continuation] = [:]
        /// spawn 世代ごとの exit continuation 履歴（0 = 最初の spawn）。再 spawn で
        /// exitContinuations[id] が上書きされても、旧世代の continuation へ発火できるよう保持する。
        /// 実 PTYManager で旧プロセスの exit が旧 exitSource クロージャ内の旧 continuation に
        /// 届く挙動を再現するために使う。
        var exitContinuationHistory: [SessionID: [AsyncStream<Int32>.Continuation]] = [:]
        var spawnCalls: [SpawnCall] = []
        var writtenCalls: [(Data, SessionID)] = []
        var killedIDs: [SessionID] = []
        var resizeCalls: [ResizeCall] = []
        /// 設定されている間、write をこのエラーで失敗させる（配送失敗パスのテスト用）。
        var writeError: PTYError?
    }

    /// 以降の write を指定エラーで失敗させる。nil で解除。
    func setWriteError(_ error: PTYError?) {
        state.withLock { $0.writeError = error }
    }

    func setSpawnSessionID(_ id: SessionID) {
        state.withLock { $0.spawnSessionID = id }
    }

    var spawnCalls: [SpawnCall] {
        state.withLock { $0.spawnCalls }
    }

    var writtenCalls: [(Data, SessionID)] {
        state.withLock { $0.writtenCalls }
    }

    var killedIDs: [SessionID] {
        state.withLock { $0.killedIDs }
    }

    var resizeCalls: [ResizeCall] {
        state.withLock { $0.resizeCalls }
    }

    /// テストから任意のタイミングで exit を発火させる（最新 spawn 世代の continuation）。1 回 yield して finish する。
    func emitExit(for id: SessionID, code: Int32) {
        let continuation = state.withLock { $0.exitContinuations[id] }
        continuation?.yield(code)
        continuation?.finish()
    }

    /// テストから PTY 出力を発火させる。購読前なら `outputStream` 接続時にフラッシュする。
    func emitOutput(for id: SessionID, data: Data) {
        state.withLock { state in
            if let continuation = state.outputContinuations[id] {
                continuation.yield(data)
            } else {
                state.pendingOutput[id, default: []].append(data)
            }
        }
    }

    /// 指定した spawn 世代（0 = 最初の spawn）の exit continuation に exit を発火する。
    /// 再 spawn 後でも旧世代へ発火できるため、「再起動前の世代のプロセスが遅れて exit する」
    /// 状況を再現できる。存在しない世代を指定した場合は何もしない。
    func emitExit(for id: SessionID, spawnGeneration: Int, code: Int32) {
        let continuation = state.withLock { state -> AsyncStream<Int32>.Continuation? in
            guard let history = state.exitContinuationHistory[id],
                  history.indices.contains(spawnGeneration) else { return nil }
            return history[spawnGeneration]
        }
        continuation?.yield(code)
        continuation?.finish()
    }

    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        let call = SpawnCall(
            command: command,
            args: args,
            env: env,
            id: id,
            initialSize: initialSize,
            workingDirectory: workingDirectory
        )
        // 実 PTYManager に合わせ、output/exit stream は spawn 内で登録する。これにより
        // 直後の outputStream(for:)/exitStream(for:) が登録済み stream を返し、
        // spawnCalls 観測時点で exit continuation が必ず存在する（取りこぼし防止）。
        let (outputStream, outputContinuation) = AsyncStream<Data>.makeStream()
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        if let id {
            state.withLock {
                $0.spawnCalls.append(call)
                $0.spawnSessionID = id
                $0.outputStreams[id] = outputStream
                $0.exitStreams[id] = exitStream
                $0.outputContinuations[id] = outputContinuation
                $0.exitContinuations[id] = exitContinuation
                $0.exitContinuationHistory[id, default: []].append(exitContinuation)
            }
            return id
        }
        return state.withLock {
            $0.spawnCalls.append(call)
            let resolvedID = $0.spawnSessionID
            $0.outputStreams[resolvedID] = outputStream
            $0.exitStreams[resolvedID] = exitStream
            $0.outputContinuations[resolvedID] = outputContinuation
            $0.exitContinuations[resolvedID] = exitContinuation
            $0.exitContinuationHistory[resolvedID, default: []].append(exitContinuation)
            return resolvedID
        }
    }

    func write(_ data: Data, to id: SessionID) async throws {
        try state.withLock { state in
            if let error = state.writeError { throw error }
            state.writtenCalls.append((data, id))
        }
    }

    func kill(_ id: SessionID) async {
        state.withLock { $0.killedIDs.append(id) }
    }

    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {
        state.withLock { $0.resizeCalls.append(ResizeCall(id: id, cols: cols, rows: rows)) }
    }

    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        // 実 PTYManager 同様、spawn で登録済みの stream を返す。未 spawn なら即 finish。
        // 同時に、spawn 済みで pendingOutput が溜まっていれば登録済み continuation 経由で
        // flush する（emitOutput が outputStream 接続前に呼ばれたケースに対応）。
        state.withLock { state -> AsyncStream<Data> in
            if let continuation = state.outputContinuations[id] {
                for data in state.pendingOutput.removeValue(forKey: id) ?? [] {
                    continuation.yield(data)
                }
            }
            return state.outputStreams[id] ?? AsyncStream { $0.finish() }
        }
    }

    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        state.withLock { $0.exitStreams[id] } ?? AsyncStream { $0.finish() }
    }
}
