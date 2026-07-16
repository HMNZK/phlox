import Foundation
import Security

/// APNs デバイストークン登録集合の永続化を抽象化する。
///
/// 本番実装は `KeychainDeviceTokenStore`（Keychain）。テストでは `InMemoryDeviceTokenStore` を使う。
/// 不変条件: トークン値をログへ出さない。
public protocol DeviceTokenStore: Sendable {
    func loadAll() throws -> [DeviceTokenRegistration]
    func upsert(_ registration: DeviceTokenRegistration) throws
    func remove(deviceToken: String) throws
}

public enum DeviceTokenStoreError: Error, Equatable {
    case keychain(OSStatus)
    case encodingFailed
    case decodingFailed
}

/// テスト・上位層モック用のインメモリ実装。
public final class InMemoryDeviceTokenStore: DeviceTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [String: DeviceTokenRegistration] = [:]

    public init() {}

    public func loadAll() throws -> [DeviceTokenRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return Array(registrations.values)
    }

    public func upsert(_ registration: DeviceTokenRegistration) throws {
        lock.lock()
        defer { lock.unlock() }
        registrations[Self.key(for: registration)] = registration
    }

    public func remove(deviceToken: String) throws {
        lock.lock()
        defer { lock.unlock() }
        registrations = registrations.filter { $0.value.deviceToken != deviceToken }
    }

    private static func key(for registration: DeviceTokenRegistration) -> String {
        "\(registration.tokenType.rawValue):\(registration.deviceToken)"
    }
}

/// Keychain（`kSecClassGenericPassword`）に登録集合を JSON で保存する本番実装。
///
/// - service は `AppFlavor` に応じて Release/Debug を分離する（`KeychainMobileTokenStore` と同型の命名）。
/// - 全登録を1エントリ（account）に JSON エンコードして保存する。
public struct KeychainDeviceTokenStore: DeviceTokenStore {
    private let service: String
    private let account: String

    public init(
        service: String = KeychainDeviceTokenStore.defaultService(for: AppFlavor.current),
        account: String = "device-tokens"
    ) {
        self.service = service
        self.account = account
    }

    /// `AppFlavor.mobileTokenKeychainService` と同型の命名規則で device token 用 service を返す。
    public static func defaultService(for flavor: AppFlavor) -> String {
        switch flavor {
        case .release: return "com.phlox.Phlox.deviceTokens"
        case .debug: return "com.phlox.Phlox.debug.deviceTokens"
        }
    }

    public func loadAll() throws -> [DeviceTokenRegistration] {
        guard let data = try loadData() else { return [] }
        let decoder = JSONDecoder()
        guard let registrations = try? decoder.decode([DeviceTokenRegistration].self, from: data) else {
            throw DeviceTokenStoreError.decodingFailed
        }
        return registrations
    }

    public func upsert(_ registration: DeviceTokenRegistration) throws {
        var all = try loadAll()
        if let index = all.firstIndex(where: {
            $0.deviceToken == registration.deviceToken && $0.tokenType == registration.tokenType
        }) {
            all[index] = registration
        } else {
            all.append(registration)
        }
        try saveAll(all)
    }

    public func remove(deviceToken: String) throws {
        var all = try loadAll()
        all.removeAll { $0.deviceToken == deviceToken }
        try saveAll(all)
    }

    /// テスト用: Keychain エントリを削除する。
    public func deleteAll() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeviceTokenStoreError.keychain(status)
        }
    }

    // MARK: - Keychain primitives

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func loadData() throws -> Data? {
        var query = baseQuery()
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
            throw DeviceTokenStoreError.keychain(status)
        }
    }

    private func saveAll(_ registrations: [DeviceTokenRegistration]) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(registrations) else {
            throw DeviceTokenStoreError.encodingFailed
        }
        try saveData(data)
    }

    private func saveData(_ data: Data) throws {
        let query = baseQuery()
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
                throw DeviceTokenStoreError.keychain(addStatus)
            }
        default:
            throw DeviceTokenStoreError.keychain(updateStatus)
        }
    }
}
