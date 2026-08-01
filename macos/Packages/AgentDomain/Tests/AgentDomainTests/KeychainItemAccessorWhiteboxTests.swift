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

@Test func secItemAccessor_usesSharedResolverForMissingEntitlement() throws {
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { errSecMissingEntitlement })

    #expect(try accessor.backend() == .fileBased)
}

@Test func secItemAccessor_rejectsItemNotFoundFromWriteProbe() throws {
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { errSecItemNotFound })

    #expect(throws: KeychainAccessError.keychain(errSecItemNotFound)) {
        _ = try accessor.backend()
    }
}

@Test func secItemAccessor_runsWriteProbeOnlyOnce() throws {
    final class ProbeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func recordProbe() -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return errSecSuccess
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    let counter = ProbeCounter()
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { counter.recordProbe() })

    _ = try accessor.backend()
    _ = try accessor.backend()

    #expect(counter.value == 1)
}
