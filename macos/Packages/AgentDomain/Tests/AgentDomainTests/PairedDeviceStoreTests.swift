import Foundation
import Security
import Testing

@testable import AgentDomain

// PairedDeviceStore の契約テスト。
// 実装（InMemory / Keychain）に依らず成立すべき upsert / remove / replaceAll の意味論（重複 id の拒否を含む）と、
// 壊れた保存データの扱い・並行 upsert・Codable の往復を固定する。

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

private func runStoreContract(_ store: any PairedDeviceStore) throws {
    // 1. 初期状態は空。
    try store.replaceAll([])
    #expect(try store.loadAll().isEmpty)

    // 2. upsert の完了後に loadAll すると、書いた端末が返る（書いた値がそのまま読める）。
    let first = makeDevice(name: "first")
    try store.upsert(first)
    #expect(try store.loadAll() == [first])

    // 3. 別 id の upsert は追加であり、既存を壊さない。
    let second = makeDevice(name: "second")
    try store.upsert(second)
    let bothIDs = Set(try store.loadAll().map(\.id))
    #expect(bothIDs == Set([first.id, second.id]))

    // 3b. 同一 id の再 upsert は置換であり、重複しない（実装に依らず成立する不変条件）。
    var renamed = second
    renamed.name = "second-renamed"
    try store.upsert(renamed)
    let afterRename = try store.loadAll()
    #expect(afterRename.count == 2)
    #expect(Set(afterRename.map(\.id)) == Set([first.id, second.id]))
    #expect(afterRename.first(where: { $0.id == second.id })?.name == "second-renamed")

    // 4. remove は対象だけを落とす。
    try store.remove(id: first.id)
    #expect(try store.loadAll().map(\.id) == [second.id])

    // 5. replaceAll は全置換であり、順序を保つ。
    let a = makeDevice(name: "a")
    let b = makeDevice(name: "b")
    try store.replaceAll([a, b])
    #expect(try store.loadAll().map(\.id) == [a.id, b.id])

    // 5b. id の一意性はストアの不変条件。重複 id を含む replaceAll は保存せず throw する。
    //     （PairedDevice は Identifiable であり、UI は id で一意に並べるため）
    var clone = a
    clone.name = "a-clone"
    #expect(throws: PairedDeviceStoreError.duplicateID(a.id)) {
        try store.replaceAll([a, b, clone])
    }
    #expect(try store.loadAll().map(\.id) == [a.id, b.id])

    // 6. purgeLegacySingleToken は端末一覧を壊さない。
    try store.purgeLegacySingleToken()
    #expect(try store.loadAll().map(\.id) == [a.id, b.id])

    try store.replaceAll([])
}

@Test func pairedDeviceStoreContract_holdsFor_inMemory() throws {
    try runStoreContract(InMemoryPairedDeviceStore())
}

@Test func pairedDeviceStoreContract_holdsFor_keychain_dataProtection() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    try runStoreContract(
        KeychainPairedDeviceStore(accessor: accessor, service: "com.phlox.test.\(UUID().uuidString)")
    )
}

@Test func pairedDeviceStoreContract_holdsFor_keychain_fileBasedFallback() throws {
    // DPK が使えない環境（ad-hoc 署名相当）でも、ストアの振る舞いは変わらない。
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)
    try runStoreContract(
        KeychainPairedDeviceStore(accessor: accessor, service: "com.phlox.test.\(UUID().uuidString)")
    )
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

@Test func pairedDevice_codableRoundTrip_preservesMobileTokenValue() throws {
    let device = PairedDevice(
        id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
        name: "書斎の iPad",
        token: MobileToken(value: "a1b2c3d4"),
        requesterSessionID: SessionID(rawValue: UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!),
        issuedAt: Date(timeIntervalSince1970: 1_000),
        pairedAt: Date(timeIntervalSince1970: 2_000)
    )

    let decoded = try JSONDecoder().decode(PairedDevice.self, from: JSONEncoder().encode(device))

    #expect(decoded == device)
}
