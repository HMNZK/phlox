import AgentDomain
import Foundation
import PTYKit

/// ユーザーターミナルの公開面を凍結するためのスタブ。
@MainActor
public final class UserTerminalController {
    public private(set) var isRunning = false
    public private(set) var sessionID: SessionID?

    public init(
        pty: any PTYManagerProtocol,
        shellPath: String,
        workingDirectory: String,
        environment: [String: String]
    ) {}

    public func ensureStarted() async throws {}

    public func send(_ input: String) async throws {}

    public func makeOutputStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func shutdown() async {}
}
