import Foundation
import Security
import Testing

@testable import AgentDomain

// KeychainItemAccessor のシーム契約テスト（PM が凍結・実装役は編集不可）。
//
// このシームは task-0 が提供し task-1 が消費する並列境界である。
// ここで固定した振る舞いは、実装（InMemory / SecItem）に依らず成立しなければならない。
// テストダブルではなく実実装に対して走らせる（SecItem 版はこの環境で使えるときだけ）。

private func runAccessorContract(_ accessor: any KeychainItemAccessor, service: String) throws {
    let account = "contract-\(UUID().uuidString)"
    defer { try? accessor.deleteItem(service: service, account: account) }

    // 1. 未保存の項目は nil。
    #expect(try accessor.loadData(service: service, account: account) == nil)

    // 2. 保存の完了後に読むと、書いた値が返る。
    let first = Data("first-value".utf8)
    try accessor.saveData(first, service: service, account: account)
    #expect(try accessor.loadData(service: service, account: account) == first)

    // 3. 同じ account への再保存は upsert（重複を作らず値が置き換わる）。
    let second = Data("second-value".utf8)
    try accessor.saveData(second, service: service, account: account)
    #expect(try accessor.loadData(service: service, account: account) == second)

    // 4. 削除の完了後は nil に戻る。
    try accessor.deleteItem(service: service, account: account)
    #expect(try accessor.loadData(service: service, account: account) == nil)

    // 5. 存在しない項目の削除は冪等（エラーにならない）。
    try accessor.deleteItem(service: service, account: account)

    // 6. account が違えば互いに影響しない。
    let other = "contract-other-\(UUID().uuidString)"
    defer { try? accessor.deleteItem(service: service, account: other) }
    try accessor.saveData(first, service: service, account: account)
    try accessor.saveData(second, service: service, account: other)
    #expect(try accessor.loadData(service: service, account: account) == first)
    #expect(try accessor.loadData(service: service, account: other) == second)
}

@Test func accessorContract_holdsFor_inMemory_dataProtection() throws {
    try runAccessorContract(
        InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess),
        service: "com.phlox.test.\(UUID().uuidString)"
    )
}

@Test func accessorContract_holdsFor_inMemory_fileBasedFallback() throws {
    try runAccessorContract(
        InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement),
        service: "com.phlox.test.\(UUID().uuidString)"
    )
}

// 本番実装 SecItemKeychainAccessor が、判定を自前で手書きせず
// KeychainBackendResolver に委ねていることを、実際の戻り値で固定する。
// この環境（未署名のテストプロセス）では DPK が使えないので .fileBased が期待値になる。
@Test func secItemAccessor_backend_isResolvedByTheSharedRule() throws {
    let accessor = SecItemKeychainAccessor()
    let resolved: KeychainBackend
    do {
        resolved = try accessor.backend()
    } catch {
        Issue.record("Keychain unavailable in this environment — backend() not verified. \(error)")
        return
    }

    // テストプロセスは keychain-access-groups entitlement を持たないため、
    // DPK への書き込みは errSecMissingEntitlement になり .fileBased へ落ちる（docs/phase0.md 2.2 の実測）。
    // 共有規則へ同じ status を渡した結果と一致すること＝本番実装が規則を手書きで複製していないこと。
    #expect(resolved == (try KeychainBackendResolver.resolve(dataProtectionWriteStatus: errSecMissingEntitlement)))
    #expect(resolved == .fileBased)
    // 2 回目以降も同じ値（プロセス内で安定）。
    #expect(try accessor.backend() == resolved)
}

@Test func accessorContract_holdsFor_secItem() throws {
    // 実 Keychain はサンドボックス・CI で使えないことがある。使えないときは黙って return せず、
    // 未検証である事実を Issue.record で残す（skip の不可視化を避ける）。
    let service = "com.phlox.test.\(UUID().uuidString)"
    let accessor = SecItemKeychainAccessor()
    do {
        _ = try accessor.backend()
        try accessor.saveData(Data("probe".utf8), service: service, account: "probe")
        try accessor.deleteItem(service: service, account: "probe")
    } catch {
        Issue.record("Keychain unavailable in this environment — SecItem accessor contract not verified. \(error)")
        return
    }

    try runAccessorContract(accessor, service: service)
}
