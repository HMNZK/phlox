import Testing
import Foundation
@testable import AgentDomain

// MARK: - 生成（32 バイト乱数 → 64 hex）

@Test func mobileToken_generate_produces64LowercaseHexCharacters() {
    let token = MobileToken.generate()

    #expect(token.value.count == 64)
    let allowed = Set("0123456789abcdef")
    #expect(token.value.allSatisfy { allowed.contains($0) })
}

@Test func mobileToken_generate_isUniquePerCall() {
    let a = MobileToken.generate()
    let b = MobileToken.generate()

    #expect(a.value != b.value)
}

@Test func mobileToken_generate_withInjectedBytes_isDeterministicHex() {
    // 32 バイトを既知の値に固定し、hex 化が安定であることを担保。
    let bytes = [UInt8](repeating: 0xAB, count: 32)
    let token = MobileToken.generate { count in
        #expect(count == 32)
        return bytes
    }

    #expect(token.value == String(repeating: "ab", count: 32))
    #expect(token.value.count == 64)
}

// MARK: - 永続化ラウンドトリップ（生成 → 保存 → ロードで同一）

@Test func provisioner_loadOrProvision_firstRun_generatesAndPersists() throws {
    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)

    let provisioned = try provisioner.loadOrProvision()

    #expect(provisioned.token.value.count == 64)
    // 保存済みであること（store に直接問い合わせて確認）。
    #expect(try store.loadToken()?.value == provisioned.token.value)
    #expect(try store.loadRequesterSessionID() == provisioned.requesterSessionID)
}

@Test func provisioner_loadOrProvision_secondRun_loadsSameTokenAndRequester() throws {
    let store = InMemoryMobileTokenStore()

    let first = try MobileTokenProvisioner(store: store).loadOrProvision()
    // 別インスタンスでロードしても同一（永続化ラウンドトリップ）。
    let second = try MobileTokenProvisioner(store: store).loadOrProvision()

    #expect(first.token.value == second.token.value)
    #expect(first.requesterSessionID == second.requesterSessionID)
}

// MARK: - 再発行で値が変わり旧トークンが無効化

@Test func provisioner_regenerate_changesTokenButKeepsRequesterSessionID() throws {
    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)
    let original = try provisioner.loadOrProvision()

    let regenerated = try provisioner.regenerate()

    #expect(regenerated.token.value != original.token.value)
    // requesterSessionID は安定（永続な特権 requester を維持）。
    #expect(regenerated.requesterSessionID == original.requesterSessionID)
    // 保存も新トークンに更新されている。
    #expect(try store.loadToken()?.value == regenerated.token.value)
}

@Test func provisioner_regenerate_isPersistedAcrossReload() throws {
    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)
    _ = try provisioner.loadOrProvision()
    let regenerated = try provisioner.regenerate()

    let reloaded = try MobileTokenProvisioner(store: store).loadOrProvision()

    #expect(reloaded.token.value == regenerated.token.value)
}

// MARK: - SessionTokenStore への register（登録後 session(forToken:) が requester を返す）

@Test func provisioner_register_makesTokenResolveToRequesterSessionID() async throws {
    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)
    let provisioned = try provisioner.loadOrProvision()

    let tokenStore = SessionTokenStore()
    await provisioner.register(provisioned, into: tokenStore)

    #expect(await tokenStore.session(forToken: provisioned.token.value) == provisioned.requesterSessionID)
}

// re-register が他セッションのトークンを巻き込まないこと。
@Test func provisioner_register_doesNotDisturbOtherSessions() async throws {
    let tokenStore = SessionTokenStore()
    // 既存の別セッションを先に登録しておく。
    let otherSession = SessionID()
    await tokenStore.register("other-session-token", for: otherSession)

    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)
    let provisioned = try provisioner.loadOrProvision()
    await provisioner.register(provisioned, into: tokenStore)

    // モバイルトークンの register が他セッションの双方向マップを壊さないこと。
    #expect(await tokenStore.session(forToken: "other-session-token") == otherSession)
    #expect(await tokenStore.token(for: otherSession) == "other-session-token")
    // モバイル側は意図どおり解決する。
    #expect(await tokenStore.session(forToken: provisioned.token.value) == provisioned.requesterSessionID)
}

// 再発行 → 再 register で旧トークンが SessionTokenStore からも解決不能になること。
@Test func provisioner_reRegisterAfterRegenerate_invalidatesOldTokenInTokenStore() async throws {
    let store = InMemoryMobileTokenStore()
    let provisioner = MobileTokenProvisioner(store: store)
    let original = try provisioner.loadOrProvision()
    let tokenStore = SessionTokenStore()
    await provisioner.register(original, into: tokenStore)

    let regenerated = try provisioner.regenerate()
    await provisioner.register(regenerated, into: tokenStore)

    #expect(await tokenStore.session(forToken: original.token.value) == nil)
    #expect(await tokenStore.session(forToken: regenerated.token.value) == regenerated.requesterSessionID)
}
