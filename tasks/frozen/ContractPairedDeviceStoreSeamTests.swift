import Foundation
import Security
import Testing

@testable import AgentDomain

// PairedDeviceStore のシーム契約テスト（PM が凍結・実装役は編集不可）。
//
// task-1 が提供し task-2（ライフサイクル）が消費する並列境界。
// ここで固定した振る舞いは、実装（InMemory / Keychain）に依らず成立しなければならない。
// テストダブルではなく実実装に対して走らせる。

private func makeDevice(name: String) -> PairedDevice {
    PairedDevice(
        id: UUID(),
        name: name,
        token: MobileToken.generate(),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 1_000),
        pairedAt: nil
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

    // 4. remove は対象だけを落とす。
    try store.remove(id: first.id)
    #expect(try store.loadAll().map(\.id) == [second.id])

    // 5. replaceAll は全置換であり、順序を保つ。
    let a = makeDevice(name: "a")
    let b = makeDevice(name: "b")
    try store.replaceAll([a, b])
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
