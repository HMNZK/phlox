import Foundation
import Security
import Testing

@testable import AgentDomain

@Test func inMemoryAccessor_saveSelectsFallbackBackend_andKeepsDataThere() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecMissingEntitlement)
    let data = Data("fallback-value".utf8)

    try accessor.saveData(data, service: "whitebox.service", account: "fallback-account")

    #expect(try accessor.backend() == .fileBased)
    #expect(try accessor.loadData(service: "whitebox.service", account: "fallback-account") == data)
    #expect(accessor.probeCount == 1)
    #expect(accessor.itemCount == 1)
}

@Test func inMemoryAccessor_savePropagatesNonEntitlementProbeFailure() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecIO)

    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        try accessor.saveData(Data("unwritten".utf8), service: "whitebox.service", account: "error-account")
    }
    #expect(accessor.itemCount == 0)
}

@Test func inMemoryAccessor_deleteOfMissingItemIsIdempotentAfterBackendSelection() throws {
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    try accessor.deleteItem(service: "whitebox.service", account: "absent-account")

    #expect(try accessor.backend() == .dataProtection)
    #expect(accessor.probeCount == 1)
    #expect(accessor.itemCount == 0)
}

@Test func secItemAccessor_usesSharedResolverForMissingEntitlement() throws {
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { errSecMissingEntitlement })

    #expect(try accessor.backend() == .fileBased)
}

@Test func secItemAccessor_rejectsItemNotFoundFromWriteProbe() throws {
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { errSecItemNotFound })

    #expect(throws: KeychainAccessError.keychain(errSecItemNotFound)) {
        _ = try accessor.backend()
    }
}

@Test func secItemAccessor_runsWriteProbeOnlyOnce() throws {
    final class ProbeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func recordProbe() -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return errSecSuccess
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    let counter = ProbeCounter()
    let accessor = SecItemKeychainAccessor(dataProtectionWriteProbe: { counter.recordProbe() })

    _ = try accessor.backend()
    _ = try accessor.backend()

    #expect(counter.value == 1)
}

// task-1 移行 finding 1 の再発防止: 旧項目は DPK フラグ無しで書かれている＝ファイルベース側にある。
// deleteItemInAllBackends は解決済みバックエンドに関係なく両ディクショナリを消せること。
@Test func inMemoryAccessor_deleteItemInAllBackends_removesFromBothBackends() throws {
    let service = "whitebox.\(UUID().uuidString)"
    let account = "both-backends"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    // 解決済みバックエンド（DPK）側に通常保存。
    try accessor.saveData(Data("dpk-value".utf8), service: service, account: account)
    // 旧ストアが残した想定のファイルベース側の項目を模す。
    accessor.seedFileBasedItem(Data("legacy-value".utf8), service: service, account: account)
    #expect(accessor.itemCount == 2)

    try accessor.deleteItemInAllBackends(service: service, account: account)

    #expect(accessor.itemCount == 0)
    #expect(try accessor.loadData(service: service, account: account) == nil)
    #expect(accessor.fileBasedItemCount(service: service) == 0)
}

@Test func inMemoryAccessor_deleteItemInAllBackends_isIdempotentWhenNothingToDelete() throws {
    let service = "whitebox.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    try accessor.deleteItemInAllBackends(service: service, account: "absent-account")
    try accessor.deleteItemInAllBackends(service: service, account: "absent-account")

    #expect(accessor.itemCount == 0)
}

// task-1 レビュー2巡目 HIGH 指摘の再発防止: DPK 側の SecItemDelete が想定外ステータスを返しても、
// ファイルベース側への削除試行を諦めてはならない（旧トークンがファイルベース側に残るのを防ぐのが
// このメソッドの存在理由のため）。
@Test func secItemAccessor_deleteItemInAllBackends_stillDeletesFileBasedSideWhenDataProtectionSideFails() throws {
    final class DeleteRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var fileBasedDeleteWasCalled = false

        func recordDelete(_ query: CFDictionary) -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            let dictionary = query as! [String: Any]
            let isDataProtectionQuery = dictionary[kSecUseDataProtectionKeychain as String] != nil
            if isDataProtectionQuery {
                // DPK 側は想定外の失敗（権限エラーでも item not found でもない）を返す。
                return errSecIO
            }
            fileBasedDeleteWasCalled = true
            return errSecSuccess
        }
    }

    let recorder = DeleteRecorder()
    let accessor = SecItemKeychainAccessor(
        dataProtectionWriteProbe: { errSecSuccess },
        deleteItemInAllBackendsHook: { recorder.recordDelete($0) }
    )

    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        try accessor.deleteItemInAllBackends(service: "whitebox.escalation-fix", account: "legacy-account")
    }
    #expect(recorder.fileBasedDeleteWasCalled)
}

// 両バックエンドが想定外ステータスを返した場合、DPK 側のステータスを優先して throw する（実装が定めた順序）。
@Test func secItemAccessor_deleteItemInAllBackends_reportsDataProtectionStatusWhenBothFail() throws {
    let accessor = SecItemKeychainAccessor(
        dataProtectionWriteProbe: { errSecSuccess },
        deleteItemInAllBackendsHook: { query in
            let dictionary = query as! [String: Any]
            let isDataProtectionQuery = dictionary[kSecUseDataProtectionKeychain as String] != nil
            return isDataProtectionQuery ? errSecIO : errSecDuplicateItem
        }
    )

    #expect(throws: KeychainAccessError.keychain(errSecIO)) {
        try accessor.deleteItemInAllBackends(service: "whitebox.escalation-fix", account: "legacy-account")
    }
}

// 両方とも想定内ステータス（success / not found / missing entitlement の組み合わせ）なら成功する。
@Test func secItemAccessor_deleteItemInAllBackends_succeedsWhenBothStatusesAreAcceptable() throws {
    let accessor = SecItemKeychainAccessor(
        dataProtectionWriteProbe: { errSecSuccess },
        deleteItemInAllBackendsHook: { query in
            let dictionary = query as! [String: Any]
            let isDataProtectionQuery = dictionary[kSecUseDataProtectionKeychain as String] != nil
            return isDataProtectionQuery ? errSecMissingEntitlement : errSecItemNotFound
        }
    )

    try accessor.deleteItemInAllBackends(service: "whitebox.escalation-fix", account: "legacy-account")
}

// task-1 レビュー3巡目 MEDIUM 指摘の再発防止: ファイルベース側「だけ」が想定外ステータスを返す場合も、
// (1) そのステータスが throw されること、(2) 両ドメインへ削除が試行済みであることを固定する。
@Test func secItemAccessor_deleteItemInAllBackends_stillAttemptsBothDomainsWhenOnlyFileBasedSideFails() throws {
    final class DeleteCallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var callOrder: [KeychainBackend] = []

        func recordDelete(_ query: CFDictionary) -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            let dictionary = query as! [String: Any]
            let isDataProtectionQuery = dictionary[kSecUseDataProtectionKeychain as String] != nil
            if isDataProtectionQuery {
                callOrder.append(.dataProtection)
                // DPK 側は想定内（成功）。
                return errSecSuccess
            }
            callOrder.append(.fileBased)
            // ファイルベース側だけが想定外の失敗を返す。
            return errSecAuthFailed
        }
    }

    let recorder = DeleteCallRecorder()
    let accessor = SecItemKeychainAccessor(
        dataProtectionWriteProbe: { errSecSuccess },
        deleteItemInAllBackendsHook: { recorder.recordDelete($0) }
    )

    #expect(throws: KeychainAccessError.keychain(errSecAuthFailed)) {
        try accessor.deleteItemInAllBackends(service: "whitebox.escalation-fix", account: "legacy-account")
    }
    #expect(recorder.callOrder == [.dataProtection, .fileBased])
}

@Test func inMemoryAccessor_seedFileBasedItem_isVisibleOnlyThroughFileBasedItemCount() throws {
    let service = "whitebox.\(UUID().uuidString)"
    let accessor = InMemoryKeychainAccessor(dataProtectionWriteStatus: errSecSuccess)

    accessor.seedFileBasedItem(Data("legacy-token".utf8), service: service, account: "mobile-token")
    accessor.seedFileBasedItem(Data("legacy-requester".utf8), service: service, account: "mobile-token.requester")
    // DPK 側の項目は fileBasedItemCount に混ざらない。
    try accessor.saveData(Data("current-value".utf8), service: service, account: "paired-devices")

    #expect(accessor.fileBasedItemCount(service: service) == 2)
}
