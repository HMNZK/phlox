import Foundation
import Security
import PhloxCore

/// Bearer トークンを Keychain に保管する `TokenStore` 実装（E3-3）。
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` を使用し、iCloud キーチェーン同期を禁止
/// （`...ThisDeviceOnly`）かつロック中アクセス不可とする。トークンは UserDefaults には保存しない。
public struct KeychainStore: TokenStore {
    let service: String
    let account: String

    public init(service: String = "com.phlox.mobile.bearer", account: String = "phlox.bearerToken") {
        self.service = service
        self.account = account
    }

    /// 検索/削除に使うベースクエリ（値・返却フラグを含まない）。テスト可能な純粋関数。
    static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 同期禁止・端末内・ロック解除時のみアクセス可のアクセシビリティ属性。
    /// （`CFString` は Sendable でないため computed で公開する。）
    static var accessibility: CFString { kSecAttrAccessibleWhenUnlockedThisDeviceOnly }

    public func save(_ token: String) async throws {
        let data = Data(token.utf8)
        // 既存を消してから追加（upsert）。
        SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
        var attributes = Self.baseQuery(service: service, account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = Self.accessibility
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public func load() async throws -> String? {
        var query = Self.baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete() async throws {
        let status = SecItemDelete(Self.baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
