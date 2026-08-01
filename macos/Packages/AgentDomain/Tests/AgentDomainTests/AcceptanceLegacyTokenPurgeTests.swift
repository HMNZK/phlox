import Foundation
import Security
import Testing

@testable import AgentDomain

// task-1 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// ユーザー決定（decision-log 2026-08-02 Q3）: 旧モデルの単一トークンは引き継がず削除する。
// 移行後、既存のペアリング済み端末は一度だけ再ペアリングが必要になる（意図した破壊的変更）。
//
// ここで固定するのは「旧項目を消すこと」と「その操作が冪等であること」の 2 点。

private let legacyTokenAccount = "mobile-token"
private let legacyRequesterAccount = "mobile-token.requester"

@Test func purgeLegacySingleToken_deletesBothLegacyAccounts() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    // 旧モデルが残した 2 項目を模す。
    try accessor.saveData(Data("legacy-token".utf8), service: service, account: legacyTokenAccount)
    try accessor.saveData(Data(UUID().uuidString.utf8), service: service, account: legacyRequesterAccount)

    let store = KeychainPairedDeviceStore(accessor: accessor, service: service)
    try store.purgeLegacySingleToken()

    #expect(try accessor.loadData(service: service, account: legacyTokenAccount) == nil)
    #expect(try accessor.loadData(service: service, account: legacyRequesterAccount) == nil)
}

@Test func purgeLegacySingleToken_isIdempotent_andSucceedsWhenNothingToPurge() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    let store = KeychainPairedDeviceStore(accessor: accessor, service: service)

    // 旧項目が無い状態でも例外にならない。
    try store.purgeLegacySingleToken()
    // 2 回目以降も同じ。
    try store.purgeLegacySingleToken()

    #expect(try accessor.loadData(service: service, account: legacyTokenAccount) == nil)
}

@Test func purgeLegacySingleToken_doesNotTouchPairedDevices() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    try accessor.saveData(Data("legacy-token".utf8), service: service, account: legacyTokenAccount)

    let store = KeychainPairedDeviceStore(accessor: accessor, service: service)
    let device = PairedDevice(
        id: UUID(),
        name: "iPhone",
        token: MobileToken.generate(),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 1_000),
        pairedAt: nil
    )
    try store.upsert(device)

    try store.purgeLegacySingleToken()

    #expect(try store.loadAll() == [device])
}
