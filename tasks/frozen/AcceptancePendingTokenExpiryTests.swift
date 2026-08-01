import Foundation
import Testing

@testable import AgentDomain

// task-2 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// ユーザー決定（decision-log 2026-08-02 Q2）: QR を表示するたびに発行されるトークンのうち、
// 使われないまま残ったものは短時間で自動失効させる。
//
// 時刻は必ず注入する（実時間 sleep は使わない）。境界（issuedAt + TTL == now）は生存側。

private func makeProvisioner(
    store: any PairedDeviceStore,
    now: @escaping @Sendable () -> Date,
    ttl: TimeInterval = 600
) -> MobileDeviceProvisioner {
    MobileDeviceProvisioner(store: store, pendingTokenTTL: ttl, now: now)
}

@Test func pruneExpired_removesUnpairedDeviceAfterTTL() throws {
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    let device = try provisioner.issueDevice(name: "未使用")

    current = current.addingTimeInterval(601)
    let removed = try provisioner.pruneExpired()

    #expect(removed == [device.id])
    #expect(try store.loadAll().isEmpty)
}

@Test func pruneExpired_keepsUnpairedDeviceExactlyAtTTLBoundary() throws {
    // issuedAt + TTL == now はまだ生存（`<` と `<=` の取り違え検出）。
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    let device = try provisioner.issueDevice(name: "境界")

    current = current.addingTimeInterval(600)
    let removed = try provisioner.pruneExpired()

    #expect(removed.isEmpty)
    #expect(try store.loadAll().map(\.id) == [device.id])
}

// ハザード2（task-2 の hazard 節）: ペアリング済みの端末は、どれだけ古くても掃除で消えない。
@Test func pruneExpired_neverRemovesPairedDevice_howeverOld() throws {
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    let device = try provisioner.issueDevice(name: "ずっと使っている iPhone")
    try provisioner.markPaired(token: device.token.value)

    current = current.addingTimeInterval(60 * 60 * 24 * 365)
    let removed = try provisioner.pruneExpired()

    #expect(removed.isEmpty)
    #expect(try store.loadAll().map(\.id) == [device.id])
}

// ハザード2 の別経路: 発行 → 期限ぎりぎりでペアリング成立 → 掃除、の順で消えないこと。
@Test func pruneExpired_afterLateMarkPaired_keepsDevice() throws {
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    let device = try provisioner.issueDevice(name: "ぎりぎり")

    current = current.addingTimeInterval(599)
    try provisioner.markPaired(token: device.token.value)
    current = current.addingTimeInterval(10_000)
    let removed = try provisioner.pruneExpired()

    #expect(removed.isEmpty)
    #expect(try store.loadAll().map(\.id) == [device.id])
}

@Test func pruneExpired_isIdempotent() throws {
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    _ = try provisioner.issueDevice(name: "未使用")

    current = current.addingTimeInterval(601)
    let first = try provisioner.pruneExpired()
    let second = try provisioner.pruneExpired()

    #expect(first.count == 1)
    #expect(second.isEmpty)
}

@Test func loadAndMigrate_prunesExpiredPendingDevices() throws {
    let store = InMemoryPairedDeviceStore()
    var current = Date(timeIntervalSince1970: 10_000)
    let provisioner = makeProvisioner(store: store, now: { current })
    let stale = try provisioner.issueDevice(name: "古い未使用")
    current = current.addingTimeInterval(601)
    let fresh = try provisioner.issueDevice(name: "新しい未使用")

    let remaining = try provisioner.loadAndMigrate()

    #expect(remaining.map(\.id) == [fresh.id])
    #expect(try store.loadAll().contains { $0.id == stale.id } == false)
}
