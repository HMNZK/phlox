import Foundation
import Security
import Testing

@testable import AgentDomain

// task-1 の受け入れテスト（PM が凍結・実装役は編集不可）。
// 固定する契約: 端末エントリの upsert / remove / replaceAll の意味論と、壊れたデータの扱い。

private func makeDevice(
    name: String,
    issuedAt: Date = Date(timeIntervalSince1970: 1_000),
    pairedAt: Date? = nil
) -> PairedDevice {
    PairedDevice(
        id: UUID(),
        name: name,
        token: MobileToken.generate(),
        requesterSessionID: SessionID(),
        issuedAt: issuedAt,
        pairedAt: pairedAt
    )
}

@Test func pairedDeviceStore_upsert_thenLoadAll_containsDevice() throws {
    let store = InMemoryPairedDeviceStore()
    let device = makeDevice(name: "iPhone")

    try store.upsert(device)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first == device)
}

@Test func pairedDeviceStore_upsertSameID_replacesInsteadOfDuplicating() throws {
    let store = InMemoryPairedDeviceStore()
    var device = makeDevice(name: "iPhone")
    try store.upsert(device)

    device.name = "リビングの iPhone"
    try store.upsert(device)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first?.name == "リビングの iPhone")
}

@Test func pairedDeviceStore_remove_dropsOnlyThatDevice() throws {
    let store = InMemoryPairedDeviceStore()
    let kept = makeDevice(name: "iPad")
    let dropped = makeDevice(name: "iPhone")
    try store.upsert(kept)
    try store.upsert(dropped)

    try store.remove(id: dropped.id)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first?.id == kept.id)
}

@Test func pairedDeviceStore_removeUnknownID_isIdempotent() throws {
    let store = InMemoryPairedDeviceStore()
    let device = makeDevice(name: "iPhone")
    try store.upsert(device)

    try store.remove(id: UUID())
    try store.remove(id: UUID())

    #expect(try store.loadAll().count == 1)
}

@Test func pairedDeviceStore_replaceAll_preservesOrder() throws {
    let store = InMemoryPairedDeviceStore()
    let a = makeDevice(name: "A")
    let b = makeDevice(name: "B")
    let c = makeDevice(name: "C")

    try store.replaceAll([c, a, b])

    let all = try store.loadAll()
    #expect(all.map(\.name) == ["C", "A", "B"])
}

@Test func pairedDeviceStore_replaceAllWithEmpty_clearsEverything() throws {
    let store = InMemoryPairedDeviceStore()
    try store.upsert(makeDevice(name: "iPhone"))

    try store.replaceAll([])

    #expect(try store.loadAll().isEmpty)
}

// Keychain 実装のラウンドトリップ。壊れたデータの扱いもここで固定する。
@Test func keychainPairedDeviceStore_roundTrip_andRejectsCorruptedPayload() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    let store = KeychainPairedDeviceStore(accessor: accessor, service: service)

    let device = makeDevice(name: "iPhone", pairedAt: Date(timeIntervalSince1970: 2_000))
    try store.upsert(device)

    let loaded = try store.loadAll()
    #expect(loaded == [device])

    // 保存済み JSON を壊すと、空配列を返して全端末を無言で失わせるのではなく throw する。
    try accessor.saveData(Data("not json".utf8), service: service, account: "paired-devices")
    #expect(throws: PairedDeviceStoreError.decodingFailed) {
        _ = try store.loadAll()
    }
}

@Test func keychainPairedDeviceStore_concurrentUpserts_doNotLoseEntries() async throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    let store = KeychainPairedDeviceStore(accessor: accessor, service: service)

    let devices = (0..<20).map { makeDevice(name: "device-\($0)") }

    await withTaskGroup(of: Void.self) { group in
        for device in devices {
            group.addTask { try? store.upsert(device) }
        }
    }

    #expect(try store.loadAll().count == devices.count)
}
