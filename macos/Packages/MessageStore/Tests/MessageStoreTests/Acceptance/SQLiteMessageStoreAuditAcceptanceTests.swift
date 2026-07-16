// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 監査所見:
// - thread() の in_reply_to に索引がなく全表スキャン → idx_messages_in_reply_to を追加する。
//   v1 DB は in_reply_to 列が無いため、索引作成は列追加（migration）後でなければならない。
// - 【推測・狭窓】user_version=0 かつ旧テーブル既存で migration を永久スキップし record が黙って失敗し続ける。
// - 保持ポリシーなしで DB 無制限肥大 → 30 日超の行を開店時に削除する（ゲート①承認）。
import AgentDomain
import Foundation
import SQLite3
import Testing
@testable import MessageStore

private enum AcceptanceSQLiteError: Error {
    case openFailed(String)
    case execFailed(String)
}

private func acceptanceDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MessageStoreAcceptance-\(UUID().uuidString).sqlite")
}

private func acceptanceRemoveDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func acceptanceExecRawSQL(at url: URL, _ sql: String) throws {
    var handle: OpaquePointer?
    let openResult = sqlite3_open_v2(
        url.path(percentEncoded: false),
        &handle,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
        nil
    )
    guard openResult == SQLITE_OK, let handle else {
        throw AcceptanceSQLiteError.openFailed(String(cString: sqlite3_errstr(openResult)))
    }
    defer { sqlite3_close_v2(handle) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
        sqlite3_free(errorMessage)
        throw AcceptanceSQLiteError.execFailed(message)
    }
}

/// in_reply_to 列を持たない旧スキーマのテーブルを用意する。userVersion で状態を制御する。
private func acceptanceCreateLegacyTable(at url: URL, userVersion: Int32) throws {
    try acceptanceExecRawSQL(
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
        PRAGMA user_version = \(userVersion);
        """
    )
}

private func acceptanceIndexExists(at url: URL, name: String) throws -> Bool {
    var handle: OpaquePointer?
    let openResult = sqlite3_open_v2(url.path(percentEncoded: false), &handle, SQLITE_OPEN_READONLY, nil)
    guard openResult == SQLITE_OK, let handle else {
        throw AcceptanceSQLiteError.openFailed(String(cString: sqlite3_errstr(openResult)))
    }
    defer { sqlite3_close_v2(handle) }

    var statement: OpaquePointer?
    let sql = "SELECT name FROM sqlite_master WHERE type='index' AND name=?"
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw AcceptanceSQLiteError.execFailed(String(cString: sqlite3_errmsg(handle)))
    }
    defer { sqlite3_finalize(statement) }
    _ = name.withCString { cString in
        sqlite3_bind_text(statement, 1, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    return sqlite3_step(statement) == SQLITE_ROW
}

private func acceptanceMessage(
    text: String,
    createdAt: Date,
    inReplyTo: UUID? = nil
) -> AgentMessage {
    AgentMessage(
        fromSession: SessionID(),
        fromName: "sender",
        toSession: SessionID(),
        toName: "recipient",
        text: text,
        submit: false,
        createdAt: createdAt,
        delivered: false,
        inReplyTo: inReplyTo
    )
}

@Test func acceptance_freshDatabase_hasInReplyToIndex() async throws {
    let url = acceptanceDatabaseURL()
    defer { acceptanceRemoveDatabase(at: url) }

    _ = try SQLiteMessageStore(databaseURL: url)

    #expect(try acceptanceIndexExists(at: url, name: "idx_messages_in_reply_to"))
}

@Test func acceptance_version1Database_gainsInReplyToIndexAfterMigration() async throws {
    let url = acceptanceDatabaseURL()
    defer { acceptanceRemoveDatabase(at: url) }
    try acceptanceCreateLegacyTable(at: url, userVersion: 1)

    // v1 → v2 移行（列追加）と索引作成の両方が行われ、開店がエラーにならないこと。
    // 索引を列追加より先に作ると "no such column: in_reply_to" で開店に失敗する（順序の回帰テスト）。
    let store = try SQLiteMessageStore(databaseURL: url)

    #expect(try acceptanceIndexExists(at: url, name: "idx_messages_in_reply_to"))

    let rootID = UUID()
    let reply = acceptanceMessage(text: "reply", createdAt: Date(), inReplyTo: rootID)
    await store.record(reply)
    let fetched = await store.message(id: reply.id)
    #expect(fetched?.inReplyTo == rootID)
}

@Test func acceptance_version0DatabaseWithLegacyTable_recoversMigration() async throws {
    // 狭窓再現: 旧コードが CREATE TABLE 後・user_version 設定前に落ちた状態
    // （テーブルは v1 形・user_version は 0）。この DB でも in_reply_to 移行が走り、
    // record → 読み出しが機能すること（現状は移行を永久スキップし record が黙って失敗し続ける）。
    let url = acceptanceDatabaseURL()
    defer { acceptanceRemoveDatabase(at: url) }
    try acceptanceCreateLegacyTable(at: url, userVersion: 0)

    let store = try SQLiteMessageStore(databaseURL: url)

    let rootID = UUID()
    let reply = acceptanceMessage(text: "recovered", createdAt: Date(), inReplyTo: rootID)
    await store.record(reply)

    let fetched = await store.message(id: reply.id)
    #expect(fetched != nil, "record が silent fail している（移行スキップの再現）")
    #expect(fetched?.inReplyTo == rootID)
    #expect(try acceptanceIndexExists(at: url, name: "idx_messages_in_reply_to"))
}

@Test func acceptance_version2DatabaseWithLegacyShape_recoversColumnBeforeIndex() async throws {
    // ステージ2レビュー指摘（task-4 差し戻し #1）の再現: 旧実装の狭窓バグを一度踏んだ DB は
    // 「v1 形テーブル（in_reply_to 列なし）のまま user_version=2 が確定」した状態で実在しうる。
    // version 条件だけで migration を判定すると列補修が永久にスキップされ、無条件の索引作成が
    // "no such column: in_reply_to" で開店 throw（＝アプリ起動不能）になる。
    // migration はスキーマ形状（列の有無・冪等）で判定し、この状態からも回復できること。
    let url = acceptanceDatabaseURL()
    defer { acceptanceRemoveDatabase(at: url) }
    try acceptanceCreateLegacyTable(at: url, userVersion: 2)

    let store = try SQLiteMessageStore(databaseURL: url)

    #expect(try acceptanceIndexExists(at: url, name: "idx_messages_in_reply_to"))

    let rootID = UUID()
    let reply = acceptanceMessage(text: "recovered-v2", createdAt: Date(), inReplyTo: rootID)
    await store.record(reply)
    let fetched = await store.message(id: reply.id)
    #expect(fetched?.inReplyTo == rootID)
}

@Test func acceptance_retention_purgesRowsOlderThan30DaysOnOpen() async throws {
    let url = acceptanceDatabaseURL()
    defer { acceptanceRemoveDatabase(at: url) }

    let first = try SQLiteMessageStore(databaseURL: url)
    let old = acceptanceMessage(text: "old", createdAt: Date().addingTimeInterval(-40 * 86_400))
    let fresh = acceptanceMessage(text: "fresh", createdAt: Date().addingTimeInterval(-60))
    await first.record(old)
    await first.record(fresh)

    // 再オープン時に 30 日超の行だけが削除されること
    let reopened = try SQLiteMessageStore(databaseURL: url)
    let recent = await reopened.recent(limit: 10)

    #expect(recent.map(\.text) == ["fresh"])
}
