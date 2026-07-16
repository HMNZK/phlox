import Foundation
import Security

/// モバイル専用トークンと、それに紐づく安定した requester SessionID の永続化を抽象化する。
///
/// 本番実装は `KeychainMobileTokenStore`（Keychain）。テストでは `InMemoryMobileTokenStore` を使う。
/// 不変条件: トークンは平文 UserDefaults・ログに残さない（Keychain に保存する）。
public protocol MobileTokenStore: Sendable {
    func loadToken() throws -> MobileToken?
    func saveToken(_ token: MobileToken) throws
    func loadRequesterSessionID() throws -> SessionID?
    func saveRequesterSessionID(_ id: SessionID) throws
    func deleteAll() throws
}

/// テスト用のインメモリ実装。UserDefaults にも Keychain にも一切書かない。
public final class InMemoryMobileTokenStore: MobileTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: MobileToken?
    private var requester: SessionID?

    public init() {}

    public func loadToken() throws -> MobileToken? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func saveToken(_ token: MobileToken) throws {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }

    public func loadRequesterSessionID() throws -> SessionID? {
        lock.lock(); defer { lock.unlock() }
        return requester
    }

    public func saveRequesterSessionID(_ id: SessionID) throws {
        lock.lock(); defer { lock.unlock() }
        self.requester = id
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        token = nil
        requester = nil
    }
}

/// Keychain（`kSecClassGenericPassword`）にトークンと requester SessionID を保存する本番実装。
///
/// - アクセシビリティ: 新規追加（SecItemAdd）時のみ `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///   を設定する（既存項目の更新＝SecItemUpdate では設定されない。upsert 方式のため一度追加された
///   項目は以後 update のみを辿り、属性が再設定されることはない）。
///   なお macOS のファイルベース Keychain（`kSecUseDataProtectionKeychain` 未指定）では、この属性は
///   実質的な保護効果が限定的である（Data Protection Keychain 前提の属性のため）。属性追加は
///   互換リスクに対し得られる保護が限定的なため見送り（ADR 0047）。本 doc は実挙動を正確に記す。
/// - 同一 service の中で token / requester を別 account で保存する。
public struct KeychainMobileTokenStore: MobileTokenStore {
    private let service: String
    private let tokenAccount: String
    private let requesterAccount: String

    /// - Parameters:
    ///   - service: Keychain item の service 名（既定はアプリ固有値）。
    ///   - account: token を保存する account。requester は `"\(account).requester"` を使う。
    public init(
        service: String = AppFlavor.current.mobileTokenKeychainService,
        account: String = "mobile-token"
    ) {
        self.service = service
        self.tokenAccount = account
        self.requesterAccount = "\(account).requester"
    }

    public func loadToken() throws -> MobileToken? {
        guard let data = try loadData(account: tokenAccount) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        return MobileToken(value: value)
    }

    public func saveToken(_ token: MobileToken) throws {
        guard let data = token.value.data(using: .utf8) else {
            throw MobileTokenStoreError.encodingFailed
        }
        try saveData(data, account: tokenAccount)
    }

    public func loadRequesterSessionID() throws -> SessionID? {
        guard let data = try loadData(account: requesterAccount) else { return nil }
        guard let uuidString = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: uuidString) else { return nil }
        return SessionID(rawValue: uuid)
    }

    public func saveRequesterSessionID(_ id: SessionID) throws {
        guard let data = id.rawValue.uuidString.data(using: .utf8) else {
            throw MobileTokenStoreError.encodingFailed
        }
        try saveData(data, account: requesterAccount)
    }

    public func deleteAll() throws {
        try delete(account: tokenAccount)
        try delete(account: requesterAccount)
    }

    // MARK: - Keychain primitives

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func loadData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw MobileTokenStoreError.keychain(status)
        }
    }

    private func saveData(_ data: Data, account: String) throws {
        // 既存があれば更新、無ければ追加（upsert）。アクセシビリティは追加時のみ設定。
        let query = baseQuery(account: account)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw MobileTokenStoreError.keychain(addStatus)
            }
        default:
            throw MobileTokenStoreError.keychain(updateStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MobileTokenStoreError.keychain(status)
        }
    }
}

public enum MobileTokenStoreError: Error, Equatable {
    case keychain(OSStatus)
    case encodingFailed
}
