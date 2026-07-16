import Foundation
import AgentDomain

public struct HookDelivery: Sendable, Equatable {
    public let sessionID: SessionID
    public let event: HookEvent
    public let nativeSessionId: String?

    public init(sessionID: SessionID, event: HookEvent, nativeSessionId: String? = nil) {
        self.sessionID = sessionID
        self.event = event
        self.nativeSessionId = nativeSessionId
    }
}

public protocol HookServerProtocol: Sendable {
    /// サーバーを起動し、bind されたポート番号を返す。
    func start() async throws -> Int

    /// 受信した (SessionID, HookEvent) のストリーム。
    var events: AsyncStream<(SessionID, HookEvent)> { get }

    /// 受信した hook のメタ情報付きストリーム。
    var deliveries: AsyncStream<HookDelivery> { get }
}
