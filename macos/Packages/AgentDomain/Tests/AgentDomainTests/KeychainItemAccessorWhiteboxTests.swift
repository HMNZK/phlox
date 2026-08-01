import Foundation
import Security
import Testing

@testable import AgentDomain

@Test func inMemoryAccessor_saveSelectsFallbackBackend_andKeepsDataThere() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)
    let data = Data("fallback-value".utf8)

    try accessor.saveData(data, service: "whitebox.service", account: "fallback-account")

    #expect(try accessor.backend() == .fileBased)
    #expect(try accessor.loadData(service: "whitebox.service", account: "fallback-account") == data)
    #expect(accessor.probeCount == 1)
    #expect(accessor.itemCount == 1)
}

@Test func inMemoryAccessor_savePropagatesNonEntitlementProbeFailure() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecIO)

    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        try accessor.saveData(Data("unwritten".utf8), service: "whitebox.service", account: "error-account")
    }
    #expect(accessor.itemCount == 0)
}

@Test func inMemoryAccessor_deleteOfMissingItemIsIdempotentAfterBackendSelection() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    try accessor.deleteItem(service: "whitebox.service", account: "absent-account")

    #expect(try accessor.backend() == .dataProtection)
    #expect(accessor.probeCount == 1)
    #expect(accessor.itemCount == 0)
}
