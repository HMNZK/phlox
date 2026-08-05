import Foundation
import Testing

@testable import AgentDomain

// task-2 の受け入れテスト（PM が凍結・実装役は編集不可）。
// 固定する契約: 端末単位の失効。失効した端末だけが解決不能になり、他端末は繋がったまま。
// これが本 run の主目的（「1 台なくしてもその 1 台だけを切れる」）なので、
// 片側だけの確認では不十分——必ず「他端末が生きている」ことも同時に確認する。

@Test func revoke_removesOnlyTargetDevice_othersRemainResolvable() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let lost = try provisioner.issueDevice(name: "なくした iPhone")
    let kept = try provisioner.issueDevice(name: "手元の iPad")
    let tokenStore = SessionTokenStore()
    await provisioner.syncRegistrations(into: tokenStore)

    try provisioner.revoke(id: lost.id)
    await provisioner.syncRegistrations(into: tokenStore)

    // 失効した端末のトークンは解決不能（＝401 になる）。
    #expect(await tokenStore.session(forToken: lost.token.value) == nil)
    // 他端末はそのまま繋がる。
    #expect(await tokenStore.session(forToken: kept.token.value) == kept.requesterSessionID)
    // 永続化からも消えている。
    #expect(try store.loadAll().map(\.id) == [kept.id])
}

@Test func revoke_unknownID_isNoOp() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let device = try provisioner.issueDevice(name: "iPhone")

    try provisioner.revoke(id: UUID())

    #expect(try store.loadAll().map(\.id) == [device.id])
}

// ハザード1（task-2 の hazard 節）: 失効の直後に掃除が古いスナップショットを書き戻して、
// 失効した端末を復活させてはならない。
@Test func pruneExpired_afterRevoke_doesNotResurrectRevokedDevice() throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { clock.now }
    )
    let revoked = try provisioner.issueDevice(name: "失効させる")
    let kept = try provisioner.issueDevice(name: "残す")
    try provisioner.markPaired(token: kept.token.value)

    try provisioner.revoke(id: revoked.id)
    clock.advance(10_000)
    _ = try provisioner.pruneExpired()

    #expect(try store.loadAll().map(\.id) == [kept.id])
}

// 失効はペアリング済みかどうかに関わらず効く。
@Test func revoke_worksForPairedDevice() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let device = try provisioner.issueDevice(name: "iPhone")
    try provisioner.markPaired(token: device.token.value)

    try provisioner.revoke(id: device.id)

    #expect(try store.loadAll().isEmpty)
}
