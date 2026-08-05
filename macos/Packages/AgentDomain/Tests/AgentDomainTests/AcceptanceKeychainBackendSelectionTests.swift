import Foundation
import Security
import Testing

@testable import AgentDomain

// task-0 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// 固定する契約:
//  1. Data Protection Keychain（DPK）を優先する。
//  2. フォールバックの引き金は errSecMissingEntitlement(-34018) だけ。それ以外は throw する。
//  3. バックエンド判定は「書き込み」で行い、プロセス内で 1 回だけ実施する（読み取りでは判定しない）。
//  4. 判定に使った sentinel を残さない。
//
// 3 が重要な理由: 実測（docs/phase0.md 2.2）で、権限が無い環境の SecItemCopyMatching は
// -34018 ではなく errSecItemNotFound(-25300) を返す。読み取りで判定すると、権限がある環境でも
// 「項目が無いだけ」を「権限が無い」と誤判定しうる。

// --- 判定規則そのもの（唯一の正本）------------------------------------------
// 本番実装もフェイクもこの関数を呼ぶ。ここを固定しておけば、どちらかの実装だけが
// 規則を手書きで複製して変異が生き残る、という穴が塞がる（レビュー指摘 [HIGH] 1）。

@Test func backendResolver_isTheSingleSourceOfTheRule() throws {
    #expect(try KeychainBackendResolver.resolve(dataProtectionWriteStatus: errSecSuccess) == .dataProtection)
    #expect(try KeychainBackendResolver.resolve(dataProtectionWriteStatus: errSecMissingEntitlement) == .fileBased)
    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        _ = try KeychainBackendResolver.resolve(dataProtectionWriteStatus: errSecIO)
    }
    // 「見つからない」は権限の話ではないので、フォールバックではなく throw。
    #expect(throws: KeychainAccessError.keychain(errSecItemNotFound)) {
        _ = try KeychainBackendResolver.resolve(dataProtectionWriteStatus: errSecItemNotFound)
    }
}

@Test func keychainAccessor_prefersDataProtection_whenEntitled() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    #expect(try accessor.backend() == .dataProtection)
}

@Test func keychainAccessor_fallsBackToFileBased_onlyOnMissingEntitlement() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)

    #expect(try accessor.backend() == .fileBased)
}

@Test func keychainAccessor_throws_onNonEntitlementError() throws {
    // -34018 以外の失敗は「権限が無い」ではないので、黙ってファイルベースへ落ちてはならない。
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecIO)

    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        _ = try accessor.backend()
    }
}

@Test func keychainAccessor_probesOnce_andCachesResult() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)

    let first = try accessor.backend()
    let second = try accessor.backend()
    try accessor.saveData(Data("v".utf8), service: "svc", account: "acct")
    _ = try accessor.loadData(service: "svc", account: "acct")
    let third = try accessor.backend()

    #expect(first == second)
    #expect(second == third)
    #expect(accessor.probeCount == 1)
}

@Test func keychainAccessor_doesNotLeaveProbeSentinelBehind() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    _ = try accessor.backend()

    // プローブ後、保存されている項目は 0 件（sentinel が削除されている）。
    #expect(accessor.itemCount == 0)
}

@Test func keychainAccessor_doesNotLeaveProbeSentinelBehind_whenFallingBack() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)

    _ = try accessor.backend()

    #expect(accessor.itemCount == 0)
}

@Test func keychainAccessor_loadDoesNotDecideBackend() throws {
    // 読み取りだけを先に行っても、バックエンド判定は書き込みプローブで行われる。
    // （読み取りの errSecItemNotFound を「権限なし」と誤読していないことの固定）
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    #expect(try accessor.loadData(service: "svc", account: "missing") == nil)
    #expect(try accessor.backend() == .dataProtection)
}
