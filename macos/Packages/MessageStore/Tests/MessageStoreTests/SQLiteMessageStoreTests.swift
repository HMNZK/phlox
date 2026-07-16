import AgentDomain
import Foundation
import SQLite3
import Testing
@testable import MessageStore

private enum SQLiteTestError: Error {
    case openFailed(String)
    case execFailed(String)
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MessageStoreTests-\(UUID().uuidString).sqlite")
}

private func removeDatabase(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove test database \(url.path): \(error)")
    }
}

private func makeMessage(
    id: UUID = UUID(),
    text: String = "hello",
    submit: Bool = false,
    delivered: Bool = false,
    createdAt: Date = Date(timeIntervalSince1970: 1_000),
    inReplyTo: UUID? = nil
) -> AgentMessage {
    AgentMessage(
        id: id,
        fromSession: SessionID(),
        fromName: "sender",
        toSession: SessionID(),
        toName: "recipient",
        text: text,
        submit: submit,
        createdAt: createdAt,
        delivered: delivered,
        inReplyTo: inReplyTo
    )
}

private func createVersion1Database(
    at url: URL,
    messageID: UUID,
    toSession: SessionID,
    createdAt: Date
) throws {
    var handle: OpaquePointer?
    let openResult = sqlite3_open_v2(
        url.path(percentEncoded: false),
        &handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
        nil
    )
    guard openResult == SQLITE_OK, let handle else {
        throw SQLiteTestError.openFailed(String(cString: sqlite3_errstr(openResult)))
    }
    defer { sqlite3_close_v2(handle) }

    try execRawSQL(
        handle,
        """
        CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            from_session TEXT,
            from_name TEXT,
            to_session TEXT NOT NULL,
            to_name TEXT,
            text TEXT NOT NULL,
            submit INTEGER NOT NULL,
            created_at REAL NOT NULL,
            delivered INTEGER NOT NULL
        );
        CREATE INDEX idx_messages_created_at ON messages(created_at);
        CREATE INDEX idx_messages_to ON messages(to_session);
        INSERT INTO messages (
            id, from_session, from_name, to_session, to_name,
            text, submit, created_at, delivered
        ) VALUES (
            '\(messageID.uuidString)', NULL, 'legacy-sender',
            '\(toSession.rawValue.uuidString)', 'legacy-recipient',
            'legacy', 0, \(createdAt.timeIntervalSince1970), 1
        );
        PRAGMA user_version = 1;
        """
    )
}

private func execRawSQL(_ db: OpaquePointer, _ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
        sqlite3_free(errorMessage)
        throw SQLiteTestError.execFailed(message)
    }
}

private func execRawSQL(at url: URL, _ sql: String) throws {
    var handle: OpaquePointer?
    let openResult = sqlite3_open_v2(
        url.path(percentEncoded: false),
        &handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
        nil
    )
    guard openResult == SQLITE_OK, let handle else {
        throw SQLiteTestError.openFailed(String(cString: sqlite3_errstr(openResult)))
    }
    defer { sqlite3_close_v2(handle) }
    try execRawSQL(handle, sql)
}

/// sqlite_master を READONLY で開いて索引の存在を確認する(索引は DB ファイルに永続する)。
private func whiteboxIndexExists(at url: URL, name: String) throws -> Bool {
    var handle: OpaquePointer?
    let openResult = sqlite3_open_v2(url.path(percentEncoded: false), &handle, SQLITE_OPEN_READONLY, nil)
    guard openResult == SQLITE_OK, let handle else {
        throw SQLiteTestError.openFailed(String(cString: sqlite3_errstr(openResult)))
    }
    defer { sqlite3_close_v2(handle) }

    var statement: OpaquePointer?
    let sql = "SELECT name FROM sqlite_master WHERE type='index' AND name=?"
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw SQLiteTestError.execFailed(String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    _ = name.withCString { cString in
        sqlite3_bind_text(statement, 1, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    return sqlite3_step(statement) == SQLITE_ROW
}

@Test func recordAndRecent_roundTrip() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let message = makeMessage(
        text: "round-trip",
        submit: true,
        delivered: true
    )

    await store.record(message)
    let recent = await store.recent(limit: 10)

    #expect(recent.count == 1)
    #expect(recent[0].id == message.id)
    #expect(recent[0].text == message.text)
    #expect(recent[0].submit == message.submit)
    #expect(recent[0].delivered == message.delivered)
    #expect(recent[0].fromSession == message.fromSession)
    #expect(recent[0].fromName == message.fromName)
    #expect(recent[0].toSession == message.toSession)
    #expect(recent[0].toName == message.toName)
    #expect(recent[0].inReplyTo == nil)
}

@Test func recordWithInReplyTo_roundTripsThroughRecentAndMessageLookup() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let rootID = UUID()
    let reply = makeMessage(text: "reply", inReplyTo: rootID)

    await store.record(reply)

    let recent = await store.recent(limit: 1)
    let fetched = try #require(await store.message(id: reply.id))

    #expect(recent.first?.inReplyTo == rootID)
    #expect(fetched == reply)
}

@Test func messageByID_returnsMatchOrNil() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let message = makeMessage(text: "lookup")

    await store.record(message)

    #expect(await store.message(id: message.id) == message)
    #expect(await store.message(id: UUID()) == nil)
}

@Test func thread_returnsRootAndRepliesOrderedByCreatedAt() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let base = Date(timeIntervalSince1970: 3_000_000)
    let root = makeMessage(text: "root", createdAt: base.addingTimeInterval(10))
    let firstReply = makeMessage(text: "first-reply", createdAt: base, inReplyTo: root.id)
    let secondReply = makeMessage(text: "second-reply", createdAt: base.addingTimeInterval(20), inReplyTo: root.id)
    let unrelated = makeMessage(text: "unrelated", createdAt: base.addingTimeInterval(5))

    await store.record(root)
    await store.record(firstReply)
    await store.record(secondReply)
    await store.record(unrelated)

    let thread = await store.thread(rootID: root.id)

    #expect(thread.map(\.id) == [firstReply.id, root.id, secondReply.id])
}

@Test func record_duplicateIDKeepsFirstMessageAndIgnoresSecond() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let id = UUID()
    let first = makeMessage(id: id, text: "first-write")
    let second = makeMessage(id: id, text: "second-write")

    await store.record(first)
    await store.record(second)

    let fetched = try #require(await store.message(id: id))
    let recent = await store.recent(limit: 10)

    // 現挙動の特性化: PRIMARY KEY 衝突時は 2 回目を黙って捨てる(上書きも例外もしない)
    #expect(fetched.text == "first-write")
    #expect(recent.count == 1)
}

@Test func record_specialCharactersInText() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let text = "quote\"newline\ncontrol\u{0001}emoji🚀"
    let message = makeMessage(text: text)

    await store.record(message)
    let recent = await store.recent(limit: 1)

    #expect(recent.count == 1)
    #expect(recent[0].text == text)
}

@Test func recent_ordersByCreatedAtDescending() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let base = Date(timeIntervalSince1970: 1_000_000)

    let oldest = makeMessage(text: "oldest", createdAt: base)
    let middle = makeMessage(text: "middle", createdAt: base.addingTimeInterval(10))
    let newest = makeMessage(text: "newest", createdAt: base.addingTimeInterval(20))

    await store.record(oldest)
    await store.record(middle)
    await store.record(newest)

    let recent = await store.recent(limit: 10)

    #expect(recent.map(\.text) == ["newest", "middle", "oldest"])
}

@Test func recent_clampsLimit() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let base = Date(timeIntervalSince1970: 2_000_000)

    for offset in 0..<5 {
        await store.record(
            makeMessage(
                text: "msg-\(offset)",
                createdAt: base.addingTimeInterval(TimeInterval(offset))
            )
        )
    }

    let fromZero = await store.recent(limit: 0)
    let fromLarge = await store.recent(limit: 10_000)

    #expect(fromZero.count == 1)
    #expect(fromLarge.count == 5)
}

@Test func openMigratesVersion1DatabaseAndPersistsInReplyTo() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let legacyID = UUID()
    let legacyToSession = SessionID()
    // 保持ポリシー(30日)導入後、1970 年固定日時だと開店時に削除されてしまうため
    // 現在時刻相対のフィクスチャに変更(PM 承認済み・アサーションは不変)。
    // createdAt は timeIntervalSince1970(大きな絶対値の double)として保存され、
    // reference-date(2001)との相互変換で小数部の下位ビット精度を失う。full-struct == を
    // 壊さないよう整数秒(1970 epoch が整数)に丸めて完全 round-trip させる。
    let base = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 3600).rounded())
    try createVersion1Database(
        at: url,
        messageID: legacyID,
        toSession: legacyToSession,
        createdAt: base
    )

    let store = try SQLiteMessageStore(databaseURL: url)
    let legacy = try #require(await store.message(id: legacyID))
    #expect(legacy.id == legacyID)
    #expect(legacy.toSession == legacyToSession)
    #expect(legacy.inReplyTo == nil)

    let reply = makeMessage(
        text: "migrated-reply",
        createdAt: base.addingTimeInterval(10),
        inReplyTo: legacyID
    )
    await store.record(reply)

    let fetchedReply = try #require(await store.message(id: reply.id))
    let thread = await store.thread(rootID: legacyID)

    #expect(fetchedReply == reply)
    #expect(thread.map(\.id) == [legacyID, reply.id])
}

// MARK: - task-4 白箱テスト(名指しハザード)

/// 保持境界: しきい値が 30 日近傍に置かれていること(off-by-一日を排除)。
/// 30日-1h は残り、30日+1h は削除される。±1h は record→reopen 間の ms オーダーのずれを
/// 十分上回るので決定論的。
@Test func retention_thresholdIsPinnedNear30Days() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let first = try SQLiteMessageStore(databaseURL: url)
    let day: TimeInterval = 86_400
    let justInside = makeMessage(text: "kept", createdAt: Date().addingTimeInterval(-(30 * day - 3600)))
    let justOutside = makeMessage(text: "purged", createdAt: Date().addingTimeInterval(-(30 * day + 3600)))
    await first.record(justInside)
    await first.record(justOutside)

    let reopened = try SQLiteMessageStore(databaseURL: url)
    let recent = await reopened.recent(limit: 10)

    #expect(recent.map(\.text) == ["kept"])
}

/// 保持削除は「開店時のみ」。同一セッション中の record では 30 日超の行も削除されない。
@Test func retention_appliesOnOpenNotDuringRecord() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    let store = try SQLiteMessageStore(databaseURL: url)
    let old = makeMessage(text: "old-in-session", createdAt: Date().addingTimeInterval(-40 * 86_400))
    await store.record(old)

    let recent = await store.recent(limit: 10)
    #expect(recent.map(\.text) == ["old-in-session"])
}

/// 新規 DB で in_reply_to 索引が作られること(索引が列より先に作られる回帰も兼ねる)。
@Test func freshDatabase_createsInReplyToIndex() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    _ = try SQLiteMessageStore(databaseURL: url)
    #expect(try whiteboxIndexExists(at: url, name: "idx_messages_in_reply_to"))
}

/// 旧コードが作った v2 DB(in_reply_to 列はあるが索引がない・user_version=2)を開いたとき、
/// 索引が後付けされること。createInReplyToIndex を version 条件の外で常に走らせる回帰。
@Test func openV2DatabaseMissingIndex_backfillsInReplyToIndex() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    try execRawSQL(
        at: url,
        """
        CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            from_session TEXT,
            from_name TEXT,
            to_session TEXT NOT NULL,
            to_name TEXT,
            text TEXT NOT NULL,
            submit INTEGER NOT NULL,
            created_at REAL NOT NULL,
            delivered INTEGER NOT NULL,
            in_reply_to TEXT
        );
        CREATE INDEX idx_messages_created_at ON messages(created_at);
        CREATE INDEX idx_messages_to ON messages(to_session);
        PRAGMA user_version = 2;
        """
    )
    #expect(try whiteboxIndexExists(at: url, name: "idx_messages_in_reply_to") == false)

    let store = try SQLiteMessageStore(databaseURL: url)
    #expect(try whiteboxIndexExists(at: url, name: "idx_messages_in_reply_to"))

    let rootID = UUID()
    let reply = makeMessage(text: "v2-reply", createdAt: Date(), inReplyTo: rootID)
    await store.record(reply)
    #expect(await store.message(id: reply.id)?.inReplyTo == rootID)
}

/// 第4状態(差し戻し #1): 旧狭窓バグを踏んだ DB は「v1 形テーブル(in_reply_to 列なし)のまま
/// user_version=2 確定」で実在しうる。migration を version でゲートすると列補修がスキップされ、
/// 無条件の索引作成が "no such column" で throw して開店に失敗する。形状ベース判定で回復すること。
@Test func openV2DatabaseWithLegacyShape_recoversColumnBeforeIndexWithoutThrowing() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    try execRawSQL(
        at: url,
        """
        CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            from_session TEXT,
            from_name TEXT,
            to_session TEXT NOT NULL,
            to_name TEXT,
            text TEXT NOT NULL,
            submit INTEGER NOT NULL,
            created_at REAL NOT NULL,
            delivered INTEGER NOT NULL
        );
        CREATE INDEX idx_messages_created_at ON messages(created_at);
        CREATE INDEX idx_messages_to ON messages(to_session);
        PRAGMA user_version = 2;
        """
    )

    // 開店が throw しないこと（version ゲートのままだと "no such column" で失敗する回帰）。
    let store = try SQLiteMessageStore(databaseURL: url)

    #expect(try whiteboxIndexExists(at: url, name: "idx_messages_in_reply_to"))

    let rootID = UUID()
    let reply = makeMessage(text: "v2-legacy-shape", createdAt: Date(), inReplyTo: rootID)
    await store.record(reply)
    #expect(await store.message(id: reply.id)?.inReplyTo == rootID)
}

/// 狭窓(user_version=0・v1形テーブル)を開いたら user_version が 2 に確定していること
/// (移行完了後の setUserVersion。再開店で狭窓が再発しない)。
@Test func narrowWindowDatabase_finalizesUserVersionAfterMigration() async throws {
    let url = temporaryDatabaseURL()
    defer { removeDatabase(at: url) }

    try execRawSQL(
        at: url,
        """
        CREATE TABLE messages(
            id TEXT PRIMARY KEY,
            from_session TEXT,
            from_name TEXT,
            to_session TEXT NOT NULL,
            to_name TEXT,
            text TEXT NOT NULL,
            submit INTEGER NOT NULL,
            created_at REAL NOT NULL,
            delivered INTEGER NOT NULL
        );
        CREATE INDEX idx_messages_created_at ON messages(created_at);
        CREATE INDEX idx_messages_to ON messages(to_session);
        PRAGMA user_version = 0;
        """
    )

    _ = try SQLiteMessageStore(databaseURL: url)

    var handle: OpaquePointer?
    #expect(sqlite3_open_v2(url.path(percentEncoded: false), &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { if let handle { sqlite3_close_v2(handle) } }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(handle, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    #expect(sqlite3_step(statement) == SQLITE_ROW)
    #expect(sqlite3_column_int(statement, 0) == 2)
}
