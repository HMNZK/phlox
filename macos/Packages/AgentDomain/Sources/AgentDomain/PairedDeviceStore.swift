import Foundation

/// ペアリング済み端末の永続化を抽象化する。
public protocol PairedDeviceStore: Sendable {
    func loadAll() throws -> [PairedDevice]
    func upsert(_ device: PairedDevice) throws
    func remove(id: UUID) throws
    func replaceAll(_ devices: [PairedDevice]) throws
    /// 旧モデル（単一トークン）の Keychain 項目を削除する。冪等。
    func purgeLegacySingleToken() throws
}

public enum PairedDeviceStoreError: Error, Equatable {
    case encodingFailed
    case decodingFailed
    case duplicateID(UUID)
}

/// `replaceAll` の入力に含まれる重複 id を検出する。id の一意性はストアの不変条件。
private func firstDuplicateID(in devices: [PairedDevice]) -> UUID? {
    var seen = Set<UUID>()
    for device in devices where !seen.insert(device.id).inserted {
        return device.id
    }
    return nil
}

/// テスト・上位層モック用のインメモリ実装。
public final class InMemoryPairedDeviceStore: PairedDeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [PairedDevice] = []

    public init() {}

    public func loadAll() throws -> [PairedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return devices
    }

    public func upsert(_ device: PairedDevice) throws {
        lock.lock()
        defer { lock.unlock() }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
    }

    public func remove(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        devices.removeAll { $0.id == id }
    }

    public func replaceAll(_ devices: [PairedDevice]) throws {
        if let duplicate = firstDuplicateID(in: devices) {
            throw PairedDeviceStoreError.duplicateID(duplicate)
        }
        lock.lock()
        defer { lock.unlock() }
        self.devices = devices
    }

    public func purgeLegacySingleToken() throws {}
}

/// Keychain の1項目に端末一覧を JSON 配列として保存する実装。
public final class KeychainPairedDeviceStore: PairedDeviceStore, @unchecked Sendable {
    private static let legacyTokenAccount = "mobile-token"
    private static let legacyRequesterAccount = "mobile-token.requester"

    private let accessor: any KeychainItemAccessor
    private let service: String
    private let account: String
    private let lock = NSLock()

    public init(
        accessor: any KeychainItemAccessor = SecItemKeychainAccessor(),
        service: String = AppFlavor.current.mobileTokenKeychainService,
        account: String = "paired-devices"
    ) {
        self.accessor = accessor
        self.service = service
        self.account = account
    }

    public func loadAll() throws -> [PairedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return try loadAllLocked()
    }

    public func upsert(_ device: PairedDevice) throws {
        lock.lock()
        defer { lock.unlock() }

        var devices = try loadAllLocked()
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        try saveAllLocked(devices)
    }

    public func remove(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var devices = try loadAllLocked()
        devices.removeAll { $0.id == id }
        try saveAllLocked(devices)
    }

    public func replaceAll(_ devices: [PairedDevice]) throws {
        if let duplicate = firstDuplicateID(in: devices) {
            throw PairedDeviceStoreError.duplicateID(duplicate)
        }
        lock.lock()
        defer { lock.unlock() }
        try saveAllLocked(devices)
    }

    public func purgeLegacySingleToken() throws {
        lock.lock()
        defer { lock.unlock() }
        try accessor.deleteItemInAllBackends(service: service, account: Self.legacyTokenAccount)
        try accessor.deleteItemInAllBackends(service: service, account: Self.legacyRequesterAccount)
    }

    private func loadAllLocked() throws -> [PairedDevice] {
        guard let data = try accessor.loadData(service: service, account: account) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PairedDevice].self, from: data)
        } catch {
            throw PairedDeviceStoreError.decodingFailed
        }
    }

    private func saveAllLocked(_ devices: [PairedDevice]) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(devices)
        } catch {
            throw PairedDeviceStoreError.encodingFailed
        }
        try accessor.saveData(data, service: service, account: account)
    }
}
