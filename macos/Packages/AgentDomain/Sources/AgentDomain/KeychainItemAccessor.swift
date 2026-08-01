import Foundation
import Security

/// SecItem がどちらの Keychain 実装を使ったか。
public enum KeychainBackend: String, Sendable, Equatable {
    case dataProtection
    case fileBased
}

/// バックエンド選択規則の唯一の正本。
public enum KeychainBackendResolver {
    /// DPK への書き込みプローブが返した OSStatus からバックエンドを決める。
    public static func resolve(dataProtectionWriteStatus status: OSStatus) throws -> KeychainBackend {
        switch status {
        case errSecSuccess:
            return .dataProtection
        case errSecMissingEntitlement:
            return .fileBased
        default:
            throw KeychainAccessError.keychain(status)
        }
    }
}

/// Keychain の生アクセス（service + account で 1 項目）を抽象化するシーム。
/// 実装は DPK を優先し、権限が無い環境でのみファイルベースへフォールバックする。
public protocol KeychainItemAccessor: Sendable {
    /// このアクセサが実際に使う実装。初回解決後は変わらない（同一プロセス内で安定）。
    func backend() throws -> KeychainBackend
    /// 見つからなければ nil。
    func loadData(service: String, account: String) throws -> Data?
    /// upsert（既存があれば更新、無ければ追加）。
    func saveData(_ data: Data, service: String, account: String) throws
    /// 冪等な削除（存在しなくてもエラーにしない）。
    func deleteItem(service: String, account: String) throws
}

public enum KeychainAccessError: Error, Equatable {
    case keychain(OSStatus)
}

/// Security.framework を通じて Keychain へアクセスする本番実装。
public final class SecItemKeychainAccessor: KeychainItemAccessor, @unchecked Sendable {
    private let lock = NSLock()
    private let dataProtectionWriteProbe: @Sendable () throws -> OSStatus
    private var resolvedBackend: KeychainBackend?

    public init() {
        dataProtectionWriteProbe = Self.runDataProtectionWriteProbe
    }

    init(dataProtectionWriteProbe: @escaping @Sendable () throws -> OSStatus) {
        self.dataProtectionWriteProbe = dataProtectionWriteProbe
    }

    public func backend() throws -> KeychainBackend {
        lock.lock()
        defer { lock.unlock() }

        if let resolvedBackend {
            return resolvedBackend
        }

        let status = try dataProtectionWriteProbe()
        let backend = try KeychainBackendResolver.resolve(dataProtectionWriteStatus: status)
        resolvedBackend = backend
        return backend
    }

    public func loadData(service: String, account: String) throws -> Data? {
        var itemQuery = Self.query(service: service, account: account, backend: try backend())
        itemQuery[kSecReturnData as String] = true
        itemQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainAccessError.keychain(errSecInternalComponent)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAccessError.keychain(status)
        }
    }

    public func saveData(_ data: Data, service: String, account: String) throws {
        let selectedBackend = try backend()
        let itemQuery = Self.query(service: service, account: account, backend: selectedBackend)
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = itemQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainAccessError.keychain(addStatus)
            }
        default:
            throw KeychainAccessError.keychain(updateStatus)
        }
    }

    public func deleteItem(service: String, account: String) throws {
        let status = SecItemDelete(Self.query(service: service, account: account, backend: try backend()) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAccessError.keychain(status)
        }
    }

    private static func query(service: String, account: String, backend: KeychainBackend) -> [String: Any] {
        var itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if backend == .dataProtection {
            itemQuery[kSecUseDataProtectionKeychain as String] = true
        }
        return itemQuery
    }

    private static func runDataProtectionWriteProbe() throws -> OSStatus {
        let probeService = "com.phlox.keychain-probe"
        let probeAccount = "data-protection-write-probe"
        var probeQuery = Self.query(service: probeService, account: probeAccount, backend: .dataProtection)
        probeQuery[kSecValueData as String] = Data([0])

        let writeStatus = SecItemAdd(probeQuery as CFDictionary, nil)
        let deleteStatus = SecItemDelete(probeQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound || deleteStatus == errSecMissingEntitlement else {
            throw KeychainAccessError.keychain(deleteStatus)
        }
        return writeStatus
    }
}

/// テスト用のプロセス内 Keychain 実装。
public final class InMemoryKeychainAccessor: KeychainItemAccessor, @unchecked Sendable {
    private let lock = NSLock()
    private let dataProtectionWriteStatus: OSStatus
    private var resolvedBackend: KeychainBackend?
    private var dataProtectionItems: [ItemKey: Data] = [:]
    private var fileBasedItems: [ItemKey: Data] = [:]
    private var storedProbeCount = 0

    public init(dataProtectionWriteStatus: OSStatus = errSecSuccess) {
        self.dataProtectionWriteStatus = dataProtectionWriteStatus
    }

    public var probeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedProbeCount
    }

    public var itemCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return dataProtectionItems.count + fileBasedItems.count
    }

    public func backend() throws -> KeychainBackend {
        lock.lock()
        defer { lock.unlock() }

        if let resolvedBackend {
            return resolvedBackend
        }

        storedProbeCount += 1
        let backend = try KeychainBackendResolver.resolve(dataProtectionWriteStatus: dataProtectionWriteStatus)
        resolvedBackend = backend
        return backend
    }

    public func loadData(service: String, account: String) throws -> Data? {
        let selectedBackend = try backend()
        let key = ItemKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        switch selectedBackend {
        case .dataProtection:
            return dataProtectionItems[key]
        case .fileBased:
            return fileBasedItems[key]
        }
    }

    public func saveData(_ data: Data, service: String, account: String) throws {
        let selectedBackend = try backend()
        let key = ItemKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        switch selectedBackend {
        case .dataProtection:
            dataProtectionItems[key] = data
        case .fileBased:
            fileBasedItems[key] = data
        }
    }

    public func deleteItem(service: String, account: String) throws {
        let selectedBackend = try backend()
        let key = ItemKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        switch selectedBackend {
        case .dataProtection:
            dataProtectionItems.removeValue(forKey: key)
        case .fileBased:
            fileBasedItems.removeValue(forKey: key)
        }
    }

    private struct ItemKey: Hashable {
        let service: String
        let account: String
    }
}
