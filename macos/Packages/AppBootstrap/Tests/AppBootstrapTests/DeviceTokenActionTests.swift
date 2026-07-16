import Foundation
import Testing
import AgentDomain
import ControlServer
import AppBootstrap

@MainActor
@Suite struct DeviceTokenActionTests {
    private let registration = DeviceTokenRegistration(
        deviceToken: "abcdef0123456789",
        bundleId: "com.phlox.mobile",
        environment: .sandbox
    )!

    @Test func registerDeviceTokenUpsertsIntoStore() async throws {
        let store = InMemoryDeviceTokenStore()
        let handler = ControlActionHandler(deviceTokenStore: store)

        let response = await handler.handle(
            ControlRequest(
                requester: nil,
                action: .registerDeviceToken(registration: registration)
            )
        )

        #expect(response.statusCode == 200)
        let stored = try store.loadAll()
        #expect(stored.count == 1)
        #expect(stored[0] == registration)
    }

    @Test func registerDeviceTokenIsIdempotentByDeviceToken() async throws {
        let store = InMemoryDeviceTokenStore()
        let handler = ControlActionHandler(deviceTokenStore: store)

        let updated = DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.updated",
            environment: .production
        )!

        _ = await handler.handle(
            ControlRequest(
                requester: nil,
                action: .registerDeviceToken(registration: registration)
            )
        )
        let second = await handler.handle(
            ControlRequest(
                requester: nil,
                action: .registerDeviceToken(registration: updated)
            )
        )

        #expect(second.statusCode == 200)
        let stored = try store.loadAll()
        #expect(stored.count == 1)
        #expect(stored[0] == updated)
    }

    @Test func registerDeviceTokenDoesNotRequireDashboard() async {
        let store = InMemoryDeviceTokenStore()
        let handler = ControlActionHandler(deviceTokenStore: store)
        handler.dashboard = nil

        let response = await handler.handle(
            ControlRequest(
                requester: nil,
                action: .registerDeviceToken(registration: registration)
            )
        )

        #expect(response.statusCode == 200)
    }

    @Test func registerDeviceTokenWithoutStoreReturns503() async {
        let handler = ControlActionHandler(deviceTokenStore: nil)

        let response = await handler.handle(
            ControlRequest(
                requester: nil,
                action: .registerDeviceToken(registration: registration)
            )
        )

        #expect(response.statusCode == 503)
    }
}
