import Testing
import Foundation
@testable import AgentDomain

// MARK: - hex 検証

@Test func deviceTokenRegistration_validHex_acceptsLowercaseEvenLength() {
    #expect(DeviceTokenRegistration.isValidHexDeviceToken("abcdef0123456789"))
    #expect(
        DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        ) != nil
    )
}

@Test func deviceTokenRegistration_rejectsEmptyHex() {
    #expect(DeviceTokenRegistration.isValidHexDeviceToken("") == false)
    #expect(
        DeviceTokenRegistration(
            deviceToken: "",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        ) == nil
    )
}

@Test func deviceTokenRegistration_rejectsOddLengthHex() {
    #expect(DeviceTokenRegistration.isValidHexDeviceToken("abc") == false)
    #expect(
        DeviceTokenRegistration(
            deviceToken: "abc",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        ) == nil
    )
}

@Test func deviceTokenRegistration_rejectsNonHexCharacters() {
    #expect(DeviceTokenRegistration.isValidHexDeviceToken("ghijkl") == false)
    #expect(
        DeviceTokenRegistration(
            deviceToken: "ghijkl",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        ) == nil
    )
}

@Test func deviceTokenRegistration_rejectsUppercaseHex() {
    // 契約1は小文字 hex を要求する。大文字は正規化せず拒否する。
    #expect(DeviceTokenRegistration.isValidHexDeviceToken("ABCDEF0123456789") == false)
    #expect(
        DeviceTokenRegistration(
            deviceToken: "ABCDEF0123456789",
            bundleId: "com.phlox.mobile",
            environment: .sandbox
        ) == nil
    )
}

// MARK: - InMemoryDeviceTokenStore

@Test func inMemoryStore_upsert_isIdempotentByDeviceToken() throws {
    let store = InMemoryDeviceTokenStore()
    let token = "abcdef0123456789"
    let first = DeviceTokenRegistration(
        deviceToken: token,
        bundleId: "com.phlox.mobile",
        environment: .sandbox
    )!
    let updated = DeviceTokenRegistration(
        deviceToken: token,
        bundleId: "com.phlox.mobile.production",
        environment: .production
    )!

    try store.upsert(first)
    try store.upsert(updated)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all[0] == updated)
}

@Test func inMemoryStore_remove_deletesMatchingToken() throws {
    let store = InMemoryDeviceTokenStore()
    let registration = DeviceTokenRegistration(
        deviceToken: "abcdef0123456789",
        bundleId: "com.phlox.mobile",
        environment: .sandbox
    )!
    let other = DeviceTokenRegistration(
        deviceToken: "0123456789abcdef",
        bundleId: "com.phlox.mobile",
        environment: .production
    )!

    try store.upsert(registration)
    try store.upsert(other)
    try store.remove(deviceToken: registration.deviceToken)

    let all = try store.loadAll()
    #expect(all == [other])
}

@Test func inMemoryStore_loadAll_returnsEmptyWhenUnset() throws {
    let store = InMemoryDeviceTokenStore()
    #expect(try store.loadAll().isEmpty)
}

// MARK: - KeychainDeviceTokenStore（実 Keychain は環境依存でゲート）

private func probeKeychainAvailability(service: String) -> (available: Bool, reason: String) {
    let store = KeychainDeviceTokenStore(service: service, account: "probe")
    let registration = DeviceTokenRegistration(
        deviceToken: "abcdef0123456789",
        bundleId: "com.phlox.mobile",
        environment: .sandbox
    )!
    do {
        try store.upsert(registration)
        let loaded = try store.loadAll()
        try store.deleteAll()
        if loaded == [registration] {
            return (true, "")
        }
        return (false, "Keychain save/load round-trip mismatch (loaded != saved)")
    } catch {
        return (false, "Keychain unavailable: \(error)")
    }
}

@Test func keychainDeviceTokenStore_roundTrip_persistsRegistrations() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let probe = probeKeychainAvailability(service: service)
    guard probe.available else {
        Issue.record("Keychain unavailable in this environment — round-trip assertion skipped. \(probe.reason)")
        return
    }

    let store = KeychainDeviceTokenStore(service: service, account: "device-tokens")
    defer { try? store.deleteAll() }

    let first = DeviceTokenRegistration(
        deviceToken: "abcdef0123456789",
        bundleId: "com.phlox.mobile",
        environment: .sandbox
    )!
    let second = DeviceTokenRegistration(
        deviceToken: "0123456789abcdef",
        bundleId: "com.phlox.mobile",
        environment: .production
    )!

    try store.upsert(first)
    try store.upsert(second)
    #expect(try store.loadAll().count == 2)

    let updated = DeviceTokenRegistration(
        deviceToken: first.deviceToken,
        bundleId: "com.phlox.mobile.updated",
        environment: .production
    )!
    try store.upsert(updated)

    let all = try store.loadAll()
    #expect(all.count == 2)
    #expect(all.contains(updated))
    #expect(all.contains(second))
}

@Test func keychainDeviceTokenStore_defaultService_followsAppFlavorPattern() {
    #expect(KeychainDeviceTokenStore.defaultService(for: .release) == "com.phlox.Phlox.deviceTokens")
    #expect(KeychainDeviceTokenStore.defaultService(for: .debug) == "com.phlox.Phlox.debug.deviceTokens")
}
