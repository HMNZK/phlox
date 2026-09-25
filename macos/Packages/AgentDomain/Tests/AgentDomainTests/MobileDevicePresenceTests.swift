import Foundation
import Testing
@testable import AgentDomain

// C-54: 設定の「接続中／未接続」。最後の要求から 30 秒以内を接続中とみなす。

@Test func presence_isConnectedWithinTheWindowOnly() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(MobileDevicePresence.isConnected(lastSeenAt: nil, now: now) == false)
    #expect(MobileDevicePresence.isConnected(lastSeenAt: now.addingTimeInterval(-30), now: now))
    #expect(MobileDevicePresence.isConnected(lastSeenAt: now.addingTimeInterval(-31), now: now) == false)
}

@Test func authenticatedTokenHook_forwardsEveryTokenToTheSeenHandler() async throws {
    let relay = MobileDevicePairingRelay()
    let (stream, continuation) = AsyncStream<String>.makeStream()
    await relay.setSeenHandler { continuation.yield($0) }
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { Date(timeIntervalSince1970: 10_000) })
    let hook = MobileBootstrap.makeAuthenticatedTokenHook(provisioner: provisioner, relay: relay, onRecordFailure: { _ in })
    hook("abc")
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == "abc")
}
