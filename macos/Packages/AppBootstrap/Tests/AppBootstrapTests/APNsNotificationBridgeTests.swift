import CryptoKit
import Foundation
import Testing
import APNsClient
import AgentDomain
@testable import AppBootstrap

@Suite struct APNsNotificationBridgeTests {
    @MainActor
    @Test func sessionDidSpawnHookKeepsNotifierAfterAnalyticsReassignment() {
        var multiplexer = SessionDidSpawnHookMultiplexer()
        var events: [String] = []

        multiplexer.setHandler(id: DashboardSessionSpawnHooks.analyticsHookID) { ref in
            events.append("analytics-1:\(ref.id)")
        }
        multiplexer.setHandler(id: DashboardSessionSpawnHooks.remoteSessionNotifierHookID) { ref in
            events.append("apns:\(ref.id)")
        }
        multiplexer.setHandler(id: DashboardSessionSpawnHooks.analyticsHookID) { ref in
            events.append("analytics-2:\(ref.id)")
        }

        multiplexer.dispatch(.builtin(.claudeCode))

        #expect(events == ["analytics-2:claudeCode", "apns:claudeCode"])
    }

    @Test func sessionCompletedPayloadMatchesContract2Snapshot() async throws {
        let store = InMemoryDeviceTokenStore()
        let registration = DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        )!
        try store.upsert(registration)
        let sender = FakeAPNsNotificationSender(results: [.success])
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: sender)

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        let calls = await sender.calls
        #expect(calls.count == 1)
        #expect(calls[0].registration == registration)
        #expect(calls[0].collapseID == "session-123:session_completed")
        let json = try Self.normalizedJSONString(calls[0].payload)
        #expect(json == """
        {"aps":{"alert":{"body":"Session completed","title":"Bright Lily"},"sound":"default","thread-id":"session-123"},"phlox":{"sessionId":"session-123","sessionName":"Bright Lily","type":"session_completed","v":1}}
        """)
    }

    @Test func approvalPendingPayloadUsesContractTypeAndCollapseID() async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        )!)
        let sender = FakeAPNsNotificationSender(results: [.success])
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: sender)

        await bridge.notify(.approvalPending(sessionId: "session-456", sessionName: "Quiet Fern"))

        let calls = await sender.calls
        #expect(calls.count == 1)
        #expect(calls[0].collapseID == "session-456:approval_pending")
        let json = try Self.normalizedJSONString(calls[0].payload)
        #expect(json == """
        {"aps":{"alert":{"body":"Approval pending","title":"Quiet Fern"},"sound":"default","thread-id":"session-456"},"phlox":{"sessionId":"session-456","sessionName":"Quiet Fern","type":"approval_pending","v":1}}
        """)
    }

    @Test func unregisteredResponseRemovesDeviceToken() async throws {
        let store = InMemoryDeviceTokenStore()
        let dead = DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        )!
        try store.upsert(dead)
        let sender = FakeAPNsNotificationSender(results: [.unregistered(reason: "Unregistered")])
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: sender)

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(try store.loadAll().isEmpty)
    }

    @Test func disabledBridgeDoesNotLoadStoreOrCallSender() async {
        let store = ThrowingDeviceTokenStore()
        let sender = FakeAPNsNotificationSender(results: [.success])
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: nil)

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(store.loadAllCallCount == 0)
        #expect(await sender.calls.isEmpty)
    }

    @Test func configuredFromEnvironmentWithCompleteCredentialsEnablesSenderAndLoadsStore() async {
        let privateKey = P256.Signing.PrivateKey()
        let store = CountingDeviceTokenStore()
        let bridge = APNsNotificationBridge.configuredFromEnvironment(
            deviceTokenStore: store,
            environment: [
                APNsNotificationBridge.keyIDEnvironmentKey: "KEY1234567",
                APNsNotificationBridge.teamIDEnvironmentKey: "TEAM123456",
                APNsNotificationBridge.authKeyPEMEnvironmentKey: privateKey.pemRepresentation,
            ]
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(store.loadAllCallCount == 1)
    }

    @Test func configuredFromEnvironmentWithMissingCredentialsIsInert() async {
        let store = CountingDeviceTokenStore()
        let bridge = APNsNotificationBridge.configuredFromEnvironment(
            deviceTokenStore: store,
            environment: [:]
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(store.loadAllCallCount == 0)
    }

    @Test func configuredFromEnvironmentWithInvalidPEMIsInert() async {
        let store = CountingDeviceTokenStore()
        let bridge = APNsNotificationBridge.configuredFromEnvironment(
            deviceTokenStore: store,
            environment: [
                APNsNotificationBridge.keyIDEnvironmentKey: "KEY1234567",
                APNsNotificationBridge.teamIDEnvironmentKey: "TEAM123456",
                APNsNotificationBridge.authKeyPEMEnvironmentKey: "not a pem",
            ]
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        #expect(store.loadAllCallCount == 0)
    }

    @Test func twoRegisteredTokensSendTwice() async throws {
        let store = InMemoryDeviceTokenStore()
        let first = DeviceTokenRegistration(
            deviceToken: "aaaaaaaaaaaaaaaa",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        )!
        let second = DeviceTokenRegistration(
            deviceToken: "bbbbbbbbbbbbbbbb",
            bundleId: "com.phlox.mobile",
            environment: .production
        )!
        try store.upsert(first)
        try store.upsert(second)
        let sender = FakeAPNsNotificationSender(results: [.success, .success])
        let bridge = APNsNotificationBridge(deviceTokenStore: store, sender: sender)

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        let calls = await sender.calls
        #expect(calls.count == 2)
        #expect(Set(calls.map(\.registration.deviceToken)) == ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"])
    }

    private static func normalizedJSONString(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: normalized, as: UTF8.self)
    }
}

private actor FakeAPNsNotificationSender: APNsNotificationSending {
    struct Call: Sendable, Equatable {
        let registration: DeviceTokenRegistration
        let collapseID: String
        let payload: Data
    }

    private var remainingResults: [APNsSendResult]
    private(set) var calls: [Call] = []

    init(results: [APNsSendResult]) {
        self.remainingResults = results
    }

    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data
    ) async throws -> APNsSendResult {
        calls.append(Call(registration: registration, collapseID: collapseID, payload: payload))
        return remainingResults.isEmpty ? .success : remainingResults.removeFirst()
    }
}

private final class ThrowingDeviceTokenStore: DeviceTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var loadAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func loadAll() throws -> [DeviceTokenRegistration] {
        lock.lock()
        count += 1
        lock.unlock()
        throw DeviceTokenStoreError.decodingFailed
    }

    func upsert(_ registration: DeviceTokenRegistration) throws {}

    func remove(deviceToken: String) throws {}
}

private final class CountingDeviceTokenStore: DeviceTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var loadAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func loadAll() throws -> [DeviceTokenRegistration] {
        lock.lock()
        count += 1
        lock.unlock()
        return []
    }

    func upsert(_ registration: DeviceTokenRegistration) throws {}

    func remove(deviceToken: String) throws {}
}
