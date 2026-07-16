import Foundation
import SQLite3
import Testing
@testable import DashboardFeature

@Suite(.serialized)
struct AppSupportMigratorTests {
    @Test func missingOldDirectoryReturnsFreshInstall() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(
            from: root.appendingPathComponent("AgentDashboard", isDirectory: true),
            to: root.appendingPathComponent("Phlox", isDirectory: true),
            options: testOptions()
        )

        #expect(outcome == .freshInstall)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Phlox").path))
    }

    @Test func existingOldDirectoryAndMissingNewDirectoryMigratesKnownFilesThroughStagingRename() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        try "do not migrate".write(to: oldURL.appendingPathComponent("ports.json"), atomically: true, encoding: .utf8)

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(
            from: oldURL,
            to: newURL,
            options: testOptions(now: Date(timeIntervalSince1970: 1_700_000_000))
        )

        #expect(outcome == .migrated)
        #expect(FileManager.default.fileExists(atPath: newURL.appendingPathComponent(AppSupportMigrator.completionMarkerName).path))
        #expect(try String(contentsOf: newURL.appendingPathComponent("projects.json"), encoding: .utf8) == #"{"projects":[]}"#)
        #expect(try String(contentsOf: newURL.appendingPathComponent("sessions.json"), encoding: .utf8) == #"{"sessions":[]}"#)
        #expect(try String(contentsOf: newURL.appendingPathComponent("workspace/session.txt"), encoding: .utf8) == "restored")
        #expect(!FileManager.default.fileExists(atPath: newURL.appendingPathComponent("ports.json").path))
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func existingNewDirectoryWithCompletionMarkerSkipsAsAlreadyMigrated() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try "{}".write(to: oldURL.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
        try "preserved".write(to: newURL.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
        try "{}".write(
            to: newURL.appendingPathComponent(AppSupportMigrator.completionMarkerName),
            atomically: true,
            encoding: .utf8
        )

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        #expect(outcome == .migrated)
        #expect(try String(contentsOf: newURL.appendingPathComponent("sessions.json"), encoding: .utf8) == "preserved")
    }

    @Test func existingNonEmptyMarkerlessNewDirectoryIsPreservedAndNotOverwritten() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try "old".write(to: oldURL.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
        try "new".write(to: newURL.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        assertSkippedExistingData(outcome)
        #expect(try String(contentsOf: newURL.appendingPathComponent("sessions.json"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: oldURL.appendingPathComponent("sessions.json"), encoding: .utf8) == "old")
    }

    @Test func existingEmptyNewDirectoryIsNotAutoMigratedBecauseDestinationExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        assertSkippedExistingData(outcome)
        #expect(!FileManager.default.fileExists(atPath: newURL.appendingPathComponent("sessions.json").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: newURL.path).isEmpty)
    }

    @Test func interruptedCopyRemovesOnlyStagingAndDoesNotThrow() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        let options = testOptions(beforeCopyingItem: { url in
            if url.lastPathComponent == "sessions.json" {
                throw TestMigrationError.injectedCopyFailure
            }
        })

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: options)

        assertFailed(outcome)
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func lockHeldByAnotherInstanceFailsImmediatelyWithoutMigrating() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        let lockURL = root.appendingPathComponent("Phlox.migration.lock")
        let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        try #require(lockDescriptor != -1)
        defer { close(lockDescriptor) }
        try #require(flock(lockDescriptor, LOCK_EX) == 0)
        defer { flock(lockDescriptor, LOCK_UN) }

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        assertFailed(outcome)
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
        #expect(try String(contentsOf: oldURL.appendingPathComponent("sessions.json"), encoding: .utf8) == #"{"sessions":[]}"#)
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func concurrentMigrationWhileLockIsHeldMigratesOnceAndOtherFailsFast() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        let renameCounter = LockedCounter()
        let firstHoldsLock = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let options = testOptions(
            renameItem: { source, destination in
                renameCounter.increment()
                try AppSupportMigrator.renameItem(from: source, to: destination)
            },
            beforeCopyingItem: { url in
                if url.lastPathComponent == "projects.json" {
                    firstHoldsLock.signal()
                    releaseFirst.wait()
                }
            }
        )

        let firstOutcome = LockedBox<MigrationOutcome>()
        let firstDone = DispatchSemaphore(value: 0)
        let thread = Thread {
            firstOutcome.set(AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: options))
            firstDone.signal()
        }
        thread.start()
        try #require(firstHoldsLock.wait(timeout: .now() + 5) == .success)

        let secondOutcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: options)
        releaseFirst.signal()
        try #require(firstDone.wait(timeout: .now() + 5) == .success)

        assertFailed(secondOutcome)
        #expect(firstOutcome.get() == .migrated)
        #expect(renameCounter.value == 1)
        #expect(FileManager.default.fileExists(atPath: newURL.appendingPathComponent(AppSupportMigrator.completionMarkerName).path))
        #expect(try String(contentsOf: newURL.appendingPathComponent("workspace/session.txt"), encoding: .utf8) == "restored")
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func sqliteWalAndShmAreBackedUpIntoConsistentSingleDatabase() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let sourceDatabase = oldURL.appendingPathComponent("messages.sqlite")
        let openHandle = try createOpenWALDatabase(at: sourceDatabase)
        defer { sqlite3_close_v2(openHandle) }

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        #expect(outcome == .migrated)
        #expect(try sqliteRows(at: newURL.appendingPathComponent("messages.sqlite")) == ["from-wal"])
        #expect(try sqliteQuickCheck(at: newURL.appendingPathComponent("messages.sqlite")) == "ok")
        #expect(!FileManager.default.fileExists(atPath: newURL.appendingPathComponent("messages.sqlite-wal").path))
        #expect(!FileManager.default.fileExists(atPath: newURL.appendingPathComponent("messages.sqlite-shm").path))
    }

    @Test func busySourceDatabaseFailsWithinBoundedTimeInsteadOfBlockingStartup() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let holder = try createExclusivelyLockedDatabase(at: oldURL.appendingPathComponent("messages.sqlite"))
        defer { sqlite3_close_v2(holder) }

        let start = ContinuousClock.now
        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())
        let elapsed = start.duration(to: .now)

        assertFailed(outcome)
        #expect(elapsed < .seconds(10))
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func oldRootSymlinkIsRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realOldURL = root.appendingPathComponent("RealAgentDashboard", isDirectory: true)
        let oldSymlinkURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: realOldURL)
        try FileManager.default.createSymbolicLink(atPath: oldSymlinkURL.path, withDestinationPath: realOldURL.path)

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldSymlinkURL, to: newURL, options: testOptions())

        assertFailed(outcome)
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
    }

    @Test func workspaceSymlinkIsPreservedWithoutFollowingExternalTarget() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        let outsideURL = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL.appendingPathComponent("workspace"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try "outside".write(to: outsideURL.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: oldURL.appendingPathComponent("workspace/link").path,
            withDestinationPath: outsideURL.path
        )

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: testOptions())

        #expect(outcome == .migrated)
        let copiedLink = newURL.appendingPathComponent("workspace/link")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copiedLink.path) == outsideURL.path)
        #expect(try isSymbolicLink(copiedLink))
    }

    @Test func crossVolumeDeviceMismatchFailsNonFatallyAndRemovesStaging() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)
        let options = testOptions(deviceIdentifier: { url in
            url.lastPathComponent.hasPrefix(".Phlox.migrating-") ? 2 : 1
        })

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(from: oldURL, to: newURL, options: options)

        assertFailed(outcome)
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
        #expect(try stagingDirectories(in: root).isEmpty)
    }

    @Test func runningLegacyApplicationSkipsMigrationForVisibleNotification() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldURL = root.appendingPathComponent("AgentDashboard", isDirectory: true)
        let newURL = root.appendingPathComponent("Phlox", isDirectory: true)
        try seedOldAppSupport(at: oldURL)

        let outcome = AppSupportMigrator.migrateAppSupportIfNeeded(
            from: oldURL,
            to: newURL,
            options: testOptions(isLegacyApplicationRunning: { _ in true })
        )

        assertSkippedExistingData(outcome)
        #expect(!FileManager.default.fileExists(atPath: newURL.path))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private enum TestMigrationError: Error {
    case injectedCopyFailure
}

private func testOptions(
    isLegacyApplicationRunning: @escaping @Sendable (Set<String>) -> Bool = { _ in false },
    deviceIdentifier: @escaping @Sendable (URL) throws -> UInt64 = AppSupportMigrator.deviceIdentifier,
    renameItem: @escaping @Sendable (URL, URL) throws -> Void = AppSupportMigrator.renameItem,
    now: Date = Date(timeIntervalSince1970: 1_700_000_000),
    beforeCopyingItem: @escaping @Sendable (URL) throws -> Void = { _ in }
) -> AppSupportMigrationOptions {
    AppSupportMigrationOptions(
        isLegacyApplicationRunning: isLegacyApplicationRunning,
        deviceIdentifier: deviceIdentifier,
        renameItem: renameItem,
        uuid: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
        now: { now },
        beforeCopyingItem: beforeCopyingItem
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-migration-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func seedOldAppSupport(at oldURL: URL) throws {
    let workspaceURL = oldURL.appendingPathComponent("workspace", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try #"{"projects":[]}"#.write(to: oldURL.appendingPathComponent("projects.json"), atomically: true, encoding: .utf8)
    try #"{"sessions":[]}"#.write(to: oldURL.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
    try "restored".write(to: workspaceURL.appendingPathComponent("session.txt"), atomically: true, encoding: .utf8)
}

private func stagingDirectories(in root: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".Phlox.migrating-") }
}

private func isSymbolicLink(_ url: URL) throws -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return (info.st_mode & S_IFMT) == S_IFLNK
}

private func assertSkippedExistingData(_ outcome: MigrationOutcome) {
    guard case .skippedExistingData = outcome else {
        Issue.record("Expected skippedExistingData, got \(outcome)")
        return
    }
}

private func assertFailed(_ outcome: MigrationOutcome) {
    guard case .failed = outcome else {
        Issue.record("Expected failed, got \(outcome)")
        return
    }
}

private func createOpenWALDatabase(at url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    let open = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard open == SQLITE_OK, let database else {
        throw SQLiteTestError.openFailed(sqliteMessage(database, fallback: open))
    }

    do {
        try sqliteExec(database, "PRAGMA journal_mode=WAL;")
        try sqliteExec(database, "CREATE TABLE messages (body TEXT NOT NULL);")
        try sqliteExec(database, "INSERT INTO messages (body) VALUES ('from-wal');")
        return database
    } catch {
        sqlite3_close_v2(database)
        throw error
    }
}

private func createExclusivelyLockedDatabase(at url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    let open = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard open == SQLITE_OK, let database else {
        throw SQLiteTestError.openFailed(sqliteMessage(database, fallback: open))
    }

    do {
        try sqliteExec(database, "CREATE TABLE messages (body TEXT NOT NULL);")
        try sqliteExec(database, "INSERT INTO messages (body) VALUES ('busy');")
        try sqliteExec(database, "BEGIN EXCLUSIVE;")
        return database
    } catch {
        sqlite3_close_v2(database)
        throw error
    }
}

private func sqliteRows(at url: URL) throws -> [String] {
    var database: OpaquePointer?
    let open = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
    guard open == SQLITE_OK, let database else {
        throw SQLiteTestError.openFailed(sqliteMessage(database, fallback: open))
    }
    defer { sqlite3_close_v2(database) }

    var statement: OpaquePointer?
    let prepare = sqlite3_prepare_v2(database, "SELECT body FROM messages ORDER BY rowid;", -1, &statement, nil)
    guard prepare == SQLITE_OK, let statement else {
        throw SQLiteTestError.execFailed(sqliteMessage(database, fallback: prepare))
    }
    defer { sqlite3_finalize(statement) }

    var rows: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        rows.append(String(cString: sqlite3_column_text(statement, 0)))
    }
    return rows
}

private func sqliteQuickCheck(at url: URL) throws -> String {
    var database: OpaquePointer?
    let open = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
    guard open == SQLITE_OK, let database else {
        throw SQLiteTestError.openFailed(sqliteMessage(database, fallback: open))
    }
    defer { sqlite3_close_v2(database) }

    var statement: OpaquePointer?
    let prepare = sqlite3_prepare_v2(database, "PRAGMA quick_check;", -1, &statement, nil)
    guard prepare == SQLITE_OK, let statement else {
        throw SQLiteTestError.execFailed(sqliteMessage(database, fallback: prepare))
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SQLiteTestError.execFailed("quick_check returned no rows")
    }
    return String(cString: sqlite3_column_text(statement, 0))
}

private func sqliteExec(_ database: OpaquePointer, _ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? sqliteMessage(database, fallback: result)
        sqlite3_free(errorMessage)
        throw SQLiteTestError.execFailed(message)
    }
}

private func sqliteMessage(_ database: OpaquePointer?, fallback: Int32) -> String {
    if let database {
        return String(cString: sqlite3_errmsg(database))
    }
    return String(cString: sqlite3_errstr(fallback))
}

private enum SQLiteTestError: Error {
    case openFailed(String)
    case execFailed(String)
}
