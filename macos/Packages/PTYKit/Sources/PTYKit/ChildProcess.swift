import AgentDomain
import Dispatch
import Foundation

public struct ChildProcess {
    public let id: SessionID
    public let pid: pid_t
    public let masterFD: Int32
    public let outputStream: AsyncStream<Data>
    public let exitStream: AsyncStream<Int32>
    public let outputContinuation: AsyncStream<Data>.Continuation
    public let exitContinuation: AsyncStream<Int32>.Continuation
    public let readSource: DispatchSourceRead
    public let exitSource: DispatchSourceProcess

    public init(
        id: SessionID,
        pid: pid_t,
        masterFD: Int32,
        outputStream: AsyncStream<Data>,
        exitStream: AsyncStream<Int32>,
        outputContinuation: AsyncStream<Data>.Continuation,
        exitContinuation: AsyncStream<Int32>.Continuation,
        readSource: DispatchSourceRead,
        exitSource: DispatchSourceProcess
    ) {
        self.id = id
        self.pid = pid
        self.masterFD = masterFD
        self.outputStream = outputStream
        self.exitStream = exitStream
        self.outputContinuation = outputContinuation
        self.exitContinuation = exitContinuation
        self.readSource = readSource
        self.exitSource = exitSource
    }
}
