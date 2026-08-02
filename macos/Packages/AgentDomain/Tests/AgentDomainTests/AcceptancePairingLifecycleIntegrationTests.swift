import Foundation
import Testing

@testable import AgentDomain

// task-4 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// 起動シーケンス（MobileBootstrap）とペアリングの一生を、アプリが実行するのと同じ順序で固定する。
// CompositionRoot が手順を再実装せず MobileBootstrap を呼ぶだけにするための契約でもある。

private func makeProvisioner(
    store: any PairedDeviceStore,
    now: @escaping @Sendable () -> Date
) -> MobileDeviceProvisioner {
    MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: now)
}

@Test func bootstrap_onFirstLaunch_returnsNoDevicesAndNoPrivilege() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let tokenStore = SessionTokenStore()

    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(result.devices.isEmpty)
    #expect(result.privilegedRequesters.isEmpty)
}

@Test func bootstrap_registersEveryDevice_andExposesTheirRequestersAsPrivileged() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let phone = try provisioner.issueDevice(name: "iPhone")
    let pad = try provisioner.issueDevice(name: "iPad")
    try provisioner.markPaired(token: phone.token.value)
    try provisioner.markPaired(token: pad.token.value)
    let tokenStore = SessionTokenStore()

    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(Set(result.devices.map(\.id)) == Set([phone.id, pad.id]))
    #expect(result.privilegedRequesters == Set([phone.requesterSessionID, pad.requesterSessionID]))
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)
    #expect(await tokenStore.session(forToken: pad.token.value) == pad.requesterSessionID)
}

@Test func bootstrap_isIdempotentAcrossRestarts() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let phone = try provisioner.issueDevice(name: "iPhone")
    try provisioner.markPaired(token: phone.token.value)

    let first = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())
    let second = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())

    #expect(first == second)
}

// 一生: QR 発行 → 認証成立 → 別端末を追加 → 1 台失効 → 残りは繋がったまま。
@Test func fullLifecycle_issueThenPairThenRevoke_keepsOtherDeviceConnected() async throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = makeProvisioner(store: store, now: { clock.now })
    let tokenStore = SessionTokenStore()

    // 1 台目: QR 発行 → スキャンして初回認証（ControlServer が解決した直後に markPaired が呼ばれる想定）。
    let phone = try provisioner.issueDevice(name: "iPhone")
    await provisioner.syncRegistrations(into: tokenStore)
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)
    try provisioner.markPaired(token: phone.token.value)

    // 2 台目を追加しても 1 台目は切れない。
    clock.advance(60)
    let pad = try provisioner.issueDevice(name: "iPad")
    await provisioner.syncRegistrations(into: tokenStore)
    try provisioner.markPaired(token: pad.token.value)
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)

    // 1 台目を失効させる。
    try provisioner.revoke(id: phone.id)
    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(await tokenStore.session(forToken: phone.token.value) == nil)
    #expect(await tokenStore.session(forToken: pad.token.value) == pad.requesterSessionID)
    #expect(result.privilegedRequesters == Set([pad.requesterSessionID]))
}

// 起動時に、使われないまま期限切れになったトークンは掃除される（Q2 の決定）。
@Test func bootstrap_prunesExpiredPendingTokens() async throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = makeProvisioner(store: store, now: { clock.now })
    let stale = try provisioner.issueDevice(name: "スキャンされなかった QR")

    clock.advance(601)
    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())

    #expect(result.devices.isEmpty)
    #expect(try store.loadAll().contains { $0.id == stale.id } == false)
}
