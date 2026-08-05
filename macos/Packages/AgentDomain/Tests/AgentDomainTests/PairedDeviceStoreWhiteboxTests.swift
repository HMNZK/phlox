import Foundation
import Security
import Testing

@testable import AgentDomain

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

// 1巡目レビュー finding 3 を受けた契約変更: id の一意性はストアの不変条件であり、
// replaceAll に重複 id を渡すと throw して保存しない（呼び出し前の状態を保つ）。
@Test func keychainPairedDeviceStore_replaceAll_withDuplicatedIDs_throwsAndPreservesPriorState() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    let store = KeychainPairedDeviceStore(accessor: accessor, service: "com.phlox.test.\(UUID().uuidString)")
    let existing = PairedDevice(
        id: UUID(),
        name: "既存の端末",
        token: MobileToken(value: "existing-token"),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 500),
        pairedAt: nil
    )
    try store.replaceAll([existing])

    let id = UUID()
    let first = PairedDevice(
        id: id,
        name: "古い名前",
        token: MobileToken(value: "first-token"),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 1_000),
        pairedAt: nil
    )
    let second = PairedDevice(
        id: id,
        name: "新しい名前",
        token: MobileToken(value: "second-token"),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 2_000),
        pairedAt: nil
    )

    #expect(throws: PairedDeviceStoreError.duplicateID(id)) {
        try store.replaceAll([first, second])
    }
    #expect(try store.loadAll() == [existing])
}

// 1巡目レビュー finding 2 の再発防止: InMemory 実装だけでなく、
// 本番の KeychainPairedDeviceStore に対しても「同一 id の再 upsert は置換」を検証する。
// upsert を append に変異させると、この white-box テストが count == 2 で落ちる。
@Test func keychainPairedDeviceStore_upsertSameID_replacesRatherThanAppending() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)
    let store = KeychainPairedDeviceStore(accessor: accessor, service: "com.phlox.test.\(UUID().uuidString)")
    var device = PairedDevice(
        id: UUID(),
        name: "iPhone",
        token: MobileToken(value: "first-token"),
        requesterSessionID: SessionID(),
        issuedAt: Date(timeIntervalSince1970: 1_000),
        pairedAt: nil
    )
    try store.upsert(device)

    device.name = "リビングの iPhone"
    try store.upsert(device)

    let all = try store.loadAll()
    #expect(all.count == 1)
    #expect(all.first?.name == "リビングの iPhone")
}
