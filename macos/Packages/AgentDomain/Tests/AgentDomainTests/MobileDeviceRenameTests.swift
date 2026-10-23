import Foundation
import Testing
@testable import AgentDomain

@Suite struct MobileDeviceRenameTests {
    @Test(arguments: [false, true], [false, true])
    func renamePersistsOnlyName(keychain: Bool, paired: Bool) async throws {
        let accessor = InMemoryKeychainAccessor()
        let store: any PairedDeviceStore = keychain
            ? KeychainPairedDeviceStore(accessor: accessor)
            : InMemoryPairedDeviceStore()
        let provisioner = MobileDeviceProvisioner(store: store)
        let device = try provisioner.issueDevice(name: "iPhone")
        let other = try provisioner.issueDevice(name: "iPad")
        let tokenStore = SessionTokenStore()
        await provisioner.syncRegistrations(into: tokenStore)
        if paired { try provisioner.markPaired(token: device.token.value) }
        var expected = try #require(try store.loadAll().first { $0.id == device.id })
        expected.name = "仕事用 iPhone 📱"

        try provisioner.rename(id: device.id, name: " \n仕事用 iPhone 📱\t ")

        let reloaded = keychain ? KeychainPairedDeviceStore(accessor: accessor) : store
        #expect(try reloaded.loadAll() == [expected, other])
        #expect(await tokenStore.session(forToken: device.token.value) == device.requesterSessionID)
    }

    @Test(arguments: ["", "   ", "\n\t　"])
    func emptyNameDoesNotChangeDevice(name: String) throws {
        let store = InMemoryPairedDeviceStore()
        let provisioner = MobileDeviceProvisioner(store: store)
        let device = try provisioner.issueDevice(name: "iPhone")

        #expect(throws: MobileDeviceProvisionerError.invalidDeviceName) {
            try provisioner.rename(id: device.id, name: name)
        }
        #expect(try store.loadAll() == [device])
    }

    @Test func revokedDeviceIsNotRecreated() throws {
        let store = InMemoryPairedDeviceStore()
        let provisioner = MobileDeviceProvisioner(store: store)
        let device = try provisioner.issueDevice(name: "iPhone")
        try provisioner.revoke(id: device.id)

        #expect(throws: MobileDeviceProvisionerError.deviceNotFound) {
            try provisioner.rename(id: device.id, name: "仕事用")
        }
        #expect(try store.loadAll().isEmpty)
    }

    @Test(arguments: [StoreFailure.read, .write])
    func storageFailureIsPropagated(failure: StoreFailure) throws {
        let device = try MobileDeviceProvisioner(store: InMemoryPairedDeviceStore()).issueDevice(name: "iPhone")
        let provisioner = MobileDeviceProvisioner(store: FailingStore(device: device, failure: failure))
        #expect(throws: failure) {
            try provisioner.rename(id: device.id, name: "仕事用")
        }
    }

    enum StoreFailure: Error, Equatable { case read, write }

    private struct FailingStore: PairedDeviceStore {
        let device: PairedDevice
        let failure: StoreFailure
        func loadAll() throws -> [PairedDevice] {
            if failure == .read { throw failure }
            return [device]
        }
        func upsert(_ device: PairedDevice) throws { throw failure }
        func remove(id: UUID) throws { throw failure }
        func replaceAll(_ devices: [PairedDevice]) throws { throw failure }
        func purgeLegacySingleToken() throws { throw failure }
    }
}
