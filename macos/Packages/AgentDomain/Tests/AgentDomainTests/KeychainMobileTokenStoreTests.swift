import Testing
import Foundation
@testable import AgentDomain

// Keychain ストアの永続化ラウンドトリップと、UserDefaults へ平文を残さないことを担保する。
// 実 Keychain は CI/サンドボックスで使えないことがある。その場合は黙って return せず、
// Issue.record で「未検証である事実」を明示記録してから return する（skip の不可視化を避ける）。

/// Keychain がこの環境で使えるか（保存→ロードのラウンドトリップが成立するか）を判定する。
/// 使えない場合はその理由を `reason` に詰めて返す（呼び出し側で Issue.record する）。
private func probeKeychainAvailability(service: String) -> (available: Bool, reason: String) {
    let store = KeychainMobileTokenStore(service: service, account: "probe")
    let token = MobileToken.generate()
    do {
        try store.saveToken(token)
        let loaded = try store.loadToken()
        try? store.deleteAll()
        if loaded?.value == token.value {
            return (true, "")
        }
        return (false, "Keychain save/load round-trip mismatch (loaded != saved)")
    } catch {
        return (false, "Keychain unavailable: \(error)")
    }
}

@Test func keychainStore_roundTrip_persistsTokenAndRequester() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let probe = probeKeychainAvailability(service: service)
    guard probe.available else {
        // 黙って return せず、検証していない事実を明示的に記録する。
        // （round-trip の assert は Keychain 利用可能環境でのみ実走する。
        //   純ロジックは MobileTokenTests / no-leak テストで別途網羅済み。）
        Issue.record("Keychain unavailable in this environment — round-trip assertion skipped. \(probe.reason)")
        return
    }
    let store = KeychainMobileTokenStore(service: service, account: "mobile-token")
    defer { try? store.deleteAll() }

    let token = MobileToken.generate()
    let session = SessionID()
    try store.saveToken(token)
    try store.saveRequesterSessionID(session)

    #expect(try store.loadToken()?.value == token.value)
    #expect(try store.loadRequesterSessionID() == session)

    // 上書きでラウンドトリップが更新されること。
    let token2 = MobileToken.generate()
    try store.saveToken(token2)
    #expect(try store.loadToken()?.value == token2.value)
}

// UserDefaults にトークンが平文で現れないこと。
// 「新規 suite が空」だけでは自明に近いため、実際に Keychain 保存経路を1回通したうえで、
// (a) 当該トークン文字列が standard / 該当 suite ドメインのどちらの UserDefaults 表現にも現れないこと、
// (b) Keychain ストアが UserDefaults を一切経由しない（書込みが発生しない）こと、を assert する。
// Keychain が使えない環境では握りつぶさず Issue.record で記録する。
@Test func keychainStore_doesNotLeakTokenToUserDefaults() throws {
    let service = "com.phlox.test.\(UUID().uuidString)"
    let probe = probeKeychainAvailability(service: service)
    guard probe.available else {
        Issue.record("Keychain unavailable in this environment — no-leak assertion (save path) skipped. \(probe.reason)")
        return
    }

    let suiteName = "com.phlox.test.defaults.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let standard = UserDefaults.standard
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = KeychainMobileTokenStore(service: service, account: "mobile-token")
    defer { try? store.deleteAll() }
    let provisioner = MobileTokenProvisioner(store: store)

    // standard ドメインの「保存前スナップショット」を取る。保存後に「モバイルトークン由来の」
    // 新規キーが増えていないことを検証する（standard 全体の差分だと並列テストや
    // システムによる書込みで偽陽性になりうるため、モバイル由来キーに限定する）。
    func mobileRelatedKeys(_ domain: UserDefaults) -> Set<String> {
        Set(domain.dictionaryRepresentation().keys.filter { $0.lowercased().contains("mobiletoken") })
    }
    let standardMobileKeysBefore = mobileRelatedKeys(standard)

    // Keychain 保存経路を実際に1回通す（握りつぶさず try）。これでトークンが永続化される。
    let provisioned = try provisioner.loadOrProvision()
    // 保存が実体として成立していること（Keychain にトークンが入ったこと）を前提として固める。
    #expect(try store.loadToken()?.value == provisioned.token.value)

    let tokenValue = provisioned.token.value
    let requesterUUID = provisioned.requesterSessionID.rawValue.uuidString

    // (a) トークン文字列・requester UUID が、テスト用 suite にも standard ドメインにも値として現れないこと。
    for domain in [defaults, standard] {
        let representation = domain.dictionaryRepresentation()
        let leakedToken = representation.values.contains { ($0 as? String) == tokenValue }
        let leakedRequester = representation.values.contains { ($0 as? String) == requesterUUID }
        #expect(leakedToken == false)
        #expect(leakedRequester == false)
        // モバイルトークン関連のキー名も現れないこと（キー経由の汚染検知）。
        let mobileKeys = representation.keys.filter { $0.lowercased().contains("mobiletoken") }
        #expect(mobileKeys.isEmpty)
    }

    // (b) Keychain 保存経路が standard ドメインへモバイルトークン由来のキーを書き込んでいないこと
    //     （UserDefaults を経由しないことの実体的担保）。before/after で増分ゼロを assert する。
    let standardMobileKeysAfter = mobileRelatedKeys(standard)
    let newlyAddedStandardMobileKeys = standardMobileKeysAfter.subtracting(standardMobileKeysBefore)
    #expect(newlyAddedStandardMobileKeys.isEmpty)
}
