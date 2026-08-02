import Foundation
import Testing

@testable import AgentDomain

// task-2 の受け入れテスト（PM が凍結・実装役は編集不可）。
// 固定する契約: 発行が既存端末を壊さないこと、1 端末 = 1 トークン = 1 requester の 1:1 対応、
// 起動時移行の冪等性、SessionTokenStore への同期。

private func makeProvisioner(
    store: any PairedDeviceStore = InMemoryPairedDeviceStore(),
    now: Date = Date(timeIntervalSince1970: 10_000),
    ttl: TimeInterval = 600
) -> MobileDeviceProvisioner {
    MobileDeviceProvisioner(store: store, pendingTokenTTL: ttl, now: { now })
}

@Test func issueDevice_returnsUnpairedEntry_with64HexToken() throws {
    let provisioner = makeProvisioner()

    let device = try provisioner.issueDevice(name: "iPhone")

    #expect(device.pairedAt == nil)
    #expect(device.name == "iPhone")
    #expect(device.token.value.count == 64)
    #expect(device.token.value.allSatisfy { $0.isHexDigit && !$0.isUppercase })
}

@Test func issueDevice_doesNotInvalidateExistingDevices() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)

    let first = try provisioner.issueDevice(name: "iPhone")
    let second = try provisioner.issueDevice(name: "iPad")

    let all = try store.loadAll()
    #expect(all.count == 2)
    // 既存端末の token / requester は一切書き換わらない。
    let reloadedFirst = try #require(all.first { $0.id == first.id })
    #expect(reloadedFirst.token == first.token)
    #expect(reloadedFirst.requesterSessionID == first.requesterSessionID)
    // 端末ごとに token も requester も異なる（1:1 対応）。
    #expect(first.token != second.token)
    #expect(first.requesterSessionID != second.requesterSessionID)
}

@Test func markPaired_setsPairedAtOnce_andDoesNotOverwrite() throws {
    let store = InMemoryPairedDeviceStore()
    let firstContact = Date(timeIntervalSince1970: 10_000)
    let laterContact = Date(timeIntervalSince1970: 20_000)
    let clock = TestClock(firstContact)
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { clock.now }
    )
    let device = try provisioner.issueDevice(name: "iPhone")

    try provisioner.markPaired(token: device.token.value)
    clock.advance(laterContact.timeIntervalSince(firstContact))
    try provisioner.markPaired(token: device.token.value)

    let reloaded = try #require(try store.loadAll().first { $0.id == device.id })
    #expect(reloaded.pairedAt == firstContact)
}

@Test func markPaired_withUnknownToken_isNoOp() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let device = try provisioner.issueDevice(name: "iPhone")

    try provisioner.markPaired(token: "0000000000000000000000000000000000000000000000000000000000000000")

    let reloaded = try #require(try store.loadAll().first { $0.id == device.id })
    #expect(reloaded.pairedAt == nil)
    #expect(try store.loadAll().count == 1)
}

@Test func loadAndMigrate_purgesLegacy_andIsIdempotent() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let device = try provisioner.issueDevice(name: "iPhone")
    try provisioner.markPaired(token: device.token.value)

    let first = try provisioner.loadAndMigrate()
    let second = try provisioner.loadAndMigrate()

    #expect(first.map(\.id) == [device.id])
    #expect(second.map(\.id) == first.map(\.id))
}

@Test func syncRegistrations_mapsEveryDeviceTokenToItsOwnRequester() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let first = try provisioner.issueDevice(name: "iPhone")
    let second = try provisioner.issueDevice(name: "iPad")
    let tokenStore = SessionTokenStore()

    await provisioner.syncRegistrations(into: tokenStore)

    #expect(await tokenStore.session(forToken: first.token.value) == first.requesterSessionID)
    #expect(await tokenStore.session(forToken: second.token.value) == second.requesterSessionID)
}
