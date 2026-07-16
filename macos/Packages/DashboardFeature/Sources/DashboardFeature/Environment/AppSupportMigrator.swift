import AppKit
import Darwin
import Foundation
import SQLite3

public enum MigrationOutcome: Equatable, Sendable {
    case migrated
    case freshInstall
    case skippedExistingData(reason: String)
    case failed(reason: String)
}

public struct AppSupportMigrationOptions: Sendable {
    public var legacyBundleIdentifiers: Set<String>
    public var isLegacyApplicationRunning: @Sendable (Set<String>) -> Bool
    public var deviceIdentifier: @Sendable (URL) throws -> UInt64
    public var renameItem: @Sendable (URL, URL) throws -> Void
    public var uuid: @Sendable () -> UUID
    public var now: @Sendable () -> Date
    public var beforeCopyingItem: @Sendable (URL) throws -> Void

    public init(
        legacyBundleIdentifiers: Set<String> = AppSupportMigrator.defaultLegacyBundleIdentifiers,
        isLegacyApplicationRunning: @escaping @Sendable (Set<String>) -> Bool = AppSupportMigrator.isLegacyApplicationRunning,
        deviceIdentifier: @escaping @Sendable (URL) throws -> UInt64 = AppSupportMigrator.deviceIdentifier,
        renameItem: @escaping @Sendable (URL, URL) throws -> Void = AppSupportMigrator.renameItem,
        uuid: @escaping @Sendable () -> UUID = { UUID() },
        now: @escaping @Sendable () -> Date = { Date() },
        beforeCopyingItem: @escaping @Sendable (URL) throws -> Void = { _ in }
    ) {
        self.legacyBundleIdentifiers = legacyBundleIdentifiers
        self.isLegacyApplicationRunning = isLegacyApplicationRunning
        self.deviceIdentifier = deviceIdentifier
        self.renameItem = renameItem
        self.uuid = uuid
        self.now = now
        self.beforeCopyingItem = beforeCopyingItem
    }
}

public enum AppSupportMigrator {
    public static let completionMarkerName = ".migration-complete.json"
    public static let defaultLegacyBundleIdentifiers: Set<String> = [
        "com.agentdashboard",
        "com.agent-dashboard",
    ]

    private static let migrationVersion = 1
    private static let lockFileName = "Phlox.migration.lock"
    private static let knownFileNames = ["projects.json", "sessions.json"]
    private static let sqliteFileName = "messages.sqlite"
    private static let workspaceDirectoryName = "workspace"

    // 起動経路から同期呼び出しされるため、BUSY 時の待ち合計を約 1 秒以下に有界化する。
    // 最悪値 ≒ リトライ回数 × (busy timeout + リトライ間隔) = 5 × (150ms + 50ms) = 1.0 秒。
    private static let sqliteBusyTimeoutMilliseconds: Int32 = 150
    private static let sqliteBusyMaxRetries = 5
    private static let sqliteBusyRetrySleepMicroseconds: UInt32 = 50_000

    public static func migrateAppSupportIfNeeded(
        from oldURL: URL,
        to newURL: URL,
        fileManager: FileManager = .default
    ) throws {
        migrateAppSupportIfNeeded(
            from: oldURL,
            to: newURL,
            fileManager: fileManager,
            options: AppSupportMigrationOptions()
        )
    }

    @discardableResult
    public static func migrateAppSupportIfNeeded(
        from oldURL: URL,
        to newURL: URL,
        fileManager: FileManager = .default,
        options: AppSupportMigrationOptions
    ) -> MigrationOutcome {
        let parentURL = newURL.deletingLastPathComponent()
        let lockURL = parentURL.appendingPathComponent(lockFileName)

        guard let lock = MigrationLock(url: lockURL) else {
            return .failed(reason: "migration lock could not be opened")
        }
        defer { lock.unlock() }

        guard lock.lock() else {
            return .failed(reason: "migration lock could not be acquired")
        }

        if pathExists(newURL) {
            if hasCompletionMarker(in: newURL) {
                return .migrated
            }
            return .skippedExistingData(reason: "Phlox Application Support already exists")
        }

        let oldType: FileSystemEntryType
        do {
            guard let type = try entryType(at: oldURL) else {
                return .freshInstall
            }
            oldType = type
        } catch {
            return .failed(reason: "old Application Support could not be inspected: \(error.localizedDescription)")
        }

        guard oldType != .symbolicLink else {
            return .failed(reason: "old Application Support root is a symbolic link")
        }
        guard oldType == .directory else {
            return .freshInstall
        }

        if options.isLegacyApplicationRunning(options.legacyBundleIdentifiers) {
            return .skippedExistingData(reason: "legacy AgentDashboard application is running")
        }

        let stagingURL = parentURL.appendingPathComponent(
            ".Phlox.migrating-\(options.uuid().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            var quickCheckResult: String?

            let sqliteSource = oldURL.appendingPathComponent(sqliteFileName)
            if let sqliteType = try entryType(at: sqliteSource) {
                try options.beforeCopyingItem(sqliteSource)
                if sqliteType == .symbolicLink {
                    try copySymbolicLink(from: sqliteSource, to: stagingURL.appendingPathComponent(sqliteFileName))
                } else if sqliteType == .regularFile {
                    quickCheckResult = try backupSQLiteDatabase(
                        from: sqliteSource,
                        to: stagingURL.appendingPathComponent(sqliteFileName)
                    )
                    removeSQLiteAuxiliaryFiles(for: stagingURL.appendingPathComponent(sqliteFileName), fileManager: fileManager)
                }
            }

            for fileName in knownFileNames {
                let source = oldURL.appendingPathComponent(fileName)
                if try entryType(at: source) != nil {
                    try options.beforeCopyingItem(source)
                    try copyEntryWithoutFollowingSymlinks(
                        from: source,
                        to: stagingURL.appendingPathComponent(fileName),
                        fileManager: fileManager,
                        options: options
                    )
                }
            }

            let workspaceSource = oldURL.appendingPathComponent(workspaceDirectoryName, isDirectory: true)
            if try entryType(at: workspaceSource) != nil {
                try options.beforeCopyingItem(workspaceSource)
                try copyEntryWithoutFollowingSymlinks(
                    from: workspaceSource,
                    to: stagingURL.appendingPathComponent(workspaceDirectoryName, isDirectory: true),
                    fileManager: fileManager,
                    options: options
                )
            }

            try writeCompletionMarker(
                in: stagingURL,
                sourcePath: oldURL.path,
                completedAt: options.now(),
                quickCheckResult: quickCheckResult ?? "not_applicable"
            )

            let parentDeviceID = try options.deviceIdentifier(parentURL)
            let stagingDeviceID = try options.deviceIdentifier(stagingURL)
            guard parentDeviceID == stagingDeviceID else {
                throw MigrationError.crossVolume
            }
            guard !pathExists(newURL) else {
                throw MigrationError.destinationAppeared
            }

            try options.renameItem(stagingURL, newURL)
            return .migrated
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            return .failed(reason: String(describing: error))
        }
    }

    public static func isLegacyApplicationRunning(bundleIdentifiers: Set<String>) -> Bool {
        bundleIdentifiers.contains { bundleIdentifier in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
            || NSWorkspace.shared.runningApplications.contains { application in
                guard let bundleIdentifier = application.bundleIdentifier else {
                    return false
                }
                return bundleIdentifiers.contains(bundleIdentifier)
            }
    }

    public static func deviceIdentifier(for url: URL) throws -> UInt64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return UInt64(info.st_dev)
    }

    public static func renameItem(from source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func hasCompletionMarker(in url: URL) -> Bool {
        pathExists(url.appendingPathComponent(completionMarkerName))
    }

    private static func pathExists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func entryType(at url: URL) throws -> FileSystemEntryType? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFREG:
            return .regularFile
        case S_IFLNK:
            return .symbolicLink
        default:
            return .other
        }
    }

    private static func copyEntryWithoutFollowingSymlinks(
        from source: URL,
        to destination: URL,
        fileManager: FileManager,
        options: AppSupportMigrationOptions
    ) throws {
        guard let type = try entryType(at: source) else {
            return
        }

        switch type {
        case .regularFile:
            try fileManager.copyItem(at: source, to: destination)
        case .symbolicLink:
            try copySymbolicLink(from: source, to: destination)
        case .directory:
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )
            for child in children {
                try options.beforeCopyingItem(child)
                try copyEntryWithoutFollowingSymlinks(
                    from: child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    fileManager: fileManager,
                    options: options
                )
            }
        case .other:
            break
        }
    }

    private static func copySymbolicLink(from source: URL, to destination: URL) throws {
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
    }

    private static func removeSQLiteAuxiliaryFiles(for databaseURL: URL, fileManager: FileManager) {
        try? fileManager.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"))
    }

    private static func writeCompletionMarker(
        in directory: URL,
        sourcePath: String,
        completedAt: Date,
        quickCheckResult: String
    ) throws {
        let marker = CompletionMarker(
            migrationVersion: migrationVersion,
            sourcePath: sourcePath,
            completedAt: ISO8601DateFormatter().string(from: completedAt),
            quickCheckResult: quickCheckResult
        )
        let data = try JSONEncoder().encode(marker)
        try data.write(to: directory.appendingPathComponent(completionMarkerName), options: .atomic)
    }

    private static func backupSQLiteDatabase(from source: URL, to destination: URL) throws -> String {
        var sourceDatabase: OpaquePointer?
        let sourceOpen = sqlite3_open_v2(source.path, &sourceDatabase, SQLITE_OPEN_READONLY, nil)
        guard sourceOpen == SQLITE_OK, let sourceDatabase else {
            throw MigrationError.sqlite("open source failed: \(sqliteMessage(sourceDatabase, fallback: sourceOpen))")
        }
        defer { sqlite3_close_v2(sourceDatabase) }

        var destinationDatabase: OpaquePointer?
        let destinationOpen = sqlite3_open_v2(
            destination.path,
            &destinationDatabase,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXCLUSIVE,
            nil
        )
        guard destinationOpen == SQLITE_OK, let destinationDatabase else {
            throw MigrationError.sqlite("open destination failed: \(sqliteMessage(destinationDatabase, fallback: destinationOpen))")
        }
        defer { sqlite3_close_v2(destinationDatabase) }

        sqlite3_busy_timeout(sourceDatabase, sqliteBusyTimeoutMilliseconds)
        sqlite3_busy_timeout(destinationDatabase, sqliteBusyTimeoutMilliseconds)

        guard let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
            throw MigrationError.sqlite("backup init failed: \(sqliteMessage(destinationDatabase, fallback: SQLITE_ERROR))")
        }
        var backupFinished = false
        defer {
            if !backupFinished {
                sqlite3_backup_finish(backup)
            }
        }

        var busyRetries = 0
        while true {
            let stepResult = sqlite3_backup_step(backup, 100)
            switch stepResult {
            case SQLITE_DONE:
                let finishResult = sqlite3_backup_finish(backup)
                backupFinished = true
                if finishResult != SQLITE_OK {
                    throw MigrationError.sqlite("backup finish failed: \(sqliteMessage(destinationDatabase, fallback: finishResult))")
                }
                try sqliteExec(destinationDatabase, "PRAGMA journal_mode=DELETE;")
                return try quickCheck(database: destinationDatabase)
            case SQLITE_OK:
                busyRetries = 0
            case SQLITE_BUSY, SQLITE_LOCKED:
                busyRetries += 1
                guard busyRetries <= sqliteBusyMaxRetries else {
                    throw MigrationError.sqlite("backup stayed busy")
                }
                usleep(sqliteBusyRetrySleepMicroseconds)
            default:
                throw MigrationError.sqlite("backup step failed: \(sqliteMessage(destinationDatabase, fallback: stepResult))")
            }
        }
    }

    private static func quickCheck(database: OpaquePointer) throws -> String {
        var statement: OpaquePointer?
        let prepare = sqlite3_prepare_v2(database, "PRAGMA quick_check;", -1, &statement, nil)
        guard prepare == SQLITE_OK, let statement else {
            throw MigrationError.sqlite("quick_check prepare failed: \(sqliteMessage(database, fallback: prepare))")
        }
        defer { sqlite3_finalize(statement) }

        var results: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw MigrationError.sqlite("quick_check failed: \(sqliteMessage(database, fallback: step))")
            }
            if let value = sqlite3_column_text(statement, 0) {
                results.append(String(cString: value))
            }
        }

        let joined = results.joined(separator: "\n")
        guard joined == "ok" else {
            throw MigrationError.sqlite("quick_check returned \(joined)")
        }
        return joined
    }

    private static func sqliteExec(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? sqliteMessage(database, fallback: result)
            sqlite3_free(errorMessage)
            throw MigrationError.sqlite(message)
        }
    }

    private static func sqliteMessage(_ database: OpaquePointer?, fallback: Int32) -> String {
        if let database {
            return String(cString: sqlite3_errmsg(database))
        }
        return String(cString: sqlite3_errstr(fallback))
    }
}

private final class MigrationLock {
    private let fileDescriptor: Int32

    init?(url: URL) {
        fileDescriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        if fileDescriptor == -1 {
            return nil
        }
    }

    deinit {
        close(fileDescriptor)
    }

    /// 起動経路から同期呼び出しされるため、ロック競合時は待たずに即失敗させる(LOCK_NB)。
    /// 二重起動時は片方だけが移行し、他方は .failed で移行をスキップする。
    func lock() -> Bool {
        flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0
    }

    func unlock() {
        flock(fileDescriptor, LOCK_UN)
    }
}

private enum FileSystemEntryType {
    case directory
    case regularFile
    case symbolicLink
    case other
}

private enum MigrationError: Error, CustomStringConvertible {
    case crossVolume
    case destinationAppeared
    case sqlite(String)

    var description: String {
        switch self {
        case .crossVolume:
            return "staging and destination parent are on different volumes"
        case .destinationAppeared:
            return "destination appeared before rename"
        case .sqlite(let message):
            return "SQLite migration failed: \(message)"
        }
    }
}

private struct CompletionMarker: Codable {
    let migrationVersion: Int
    let sourcePath: String
    let completedAt: String
    let quickCheckResult: String

    enum CodingKeys: String, CodingKey {
        case migrationVersion
        case sourcePath
        case completedAt
        case quickCheckResult = "quick_check"
    }
}
