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
    /// DPK / ファイルベースの**両方**の実装から削除する。冪等（どちらに無くてもエラーにしない）。
    /// 旧モデルの移行専用。通常の削除は deleteItem を使う。
    func deleteItemInAllBackends(service: String, account: String) throws
}

public enum KeychainAccessError: Error, Equatable {
    case keychain(OSStatus)
}

/// Security.framework を通じて Keychain へアクセスする本番実装。
public final class SecItemKeychainAccessor: KeychainItemAccessor, @unchecked Sendable {
    private let lock = NSLock()
    private let dataProtectionWriteProbe: @Sendable () throws -> OSStatus
    /// テスト専用フック: deleteItemInAllBackends が両バックエンドへ出す SecItemDelete を差し替える。
    /// 既存4メソッドはこのフックを使わず、常に SecItemDelete を直接呼ぶ（振る舞い不変）。
    private let deleteItemInAllBackendsHook: @Sendable (CFDictionary) -> OSStatus
    private var resolvedBackend: KeychainBackend?

    public init() {
        dataProtectionWriteProbe = Self.runDataProtectionWriteProbe
        deleteItemInAllBackendsHook = SecItemDelete
    }

    init(
        dataProtectionWriteProbe: @escaping @Sendable () throws -> OSStatus,
        deleteItemInAllBackendsHook: @escaping @Sendable (CFDictionary) -> OSStatus = SecItemDelete
    ) {
        self.dataProtectionWriteProbe = dataProtectionWriteProbe
        self.deleteItemInAllBackendsHook = deleteItemInAllBackendsHook
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

    public func deleteItemInAllBackends(service: String, account: String) throws {
        // 両ドメインへ必ず削除を試みる。片方が想定外ステータスを返しても、もう片方の削除を諦めない
        // （旧モデルのファイルベース側トークンが残るのを防ぐのがこのメソッドの存在理由のため）。
        let dataProtectionStatus = deleteItemInAllBackendsHook(
            Self.query(service: service, account: account, backend: .dataProtection) as CFDictionary
        )
        let fileBasedStatus = deleteItemInAllBackendsHook(
            Self.query(service: service, account: account, backend: .fileBased) as CFDictionary
        )

        // 複数が想定外なら DPK 側を優先して報告する。
        for status in [dataProtectionStatus, fileBasedStatus] where !Self.isAcceptableDeleteInAllBackendsStatus(status) {
            throw KeychainAccessError.keychain(status)
        }
    }

    private static func isAcceptableDeleteInAllBackendsStatus(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement
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

    public func deleteItemInAllBackends(service: String, account: String) throws {
        let key = ItemKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        dataProtectionItems.removeValue(forKey: key)
        fileBasedItems.removeValue(forKey: key)
    }

    /// テスト専用: 解決済みバックエンドに依らずファイルベース側へ直接書く（旧ストアが残した項目を模す）。
    public func seedFileBasedItem(_ data: Data, service: String, account: String) {
        let key = ItemKey(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        fileBasedItems[key] = data
    }

    /// テスト専用: 指定 service でファイルベース側に残っている項目数。
    public func fileBasedItemCount(service: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return fileBasedItems.keys.filter { $0.service == service }.count
    }

    private struct ItemKey: Hashable {
        let service: String
        let account: String
    }
}
