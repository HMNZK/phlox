import AgentDomain
import Foundation
import os
import SQLite3

private let schemaVersion: Int32 = 2
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum MessageStoreError: Error, Sendable {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case databaseClosed
}

/// messages テーブルの列定義の単一ソース。
/// rawValue が SELECT/INSERT の列順(= 結果セットの列番号・バインド位置)に対応する。
private enum MessageColumn: Int32, CaseIterable {
    case id
    case fromSession
    case fromName
    case toSession
    case toName
    case text
    case submit
    case createdAt
    case delivered
    case inReplyTo

    var name: String {
        switch self {
        case .id: "id"
        case .fromSession: "from_session"
        case .fromName: "from_name"
        case .toSession: "to_session"
        case .toName: "to_name"
        case .text: "text"
        case .submit: "submit"
        case .createdAt: "created_at"
        case .delivered: "delivered"
        case .inReplyTo: "in_reply_to"
        }
    }

    /// バインドパラメータの位置(1 始まり)
    var bindIndex: Int32 { rawValue + 1 }

    static let list = allCases.map(\.name).joined(separator: ", ")
    static let placeholders = allCases.map { _ in "?" }.joined(separator: ", ")
}

private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close_v2(pointer)
    }
}

public actor SQLiteMessageStore: MessageStoreProtocol {
    private let connection: SQLiteConnection
    /// 開店経路(init は actor 分離が確立する前で self を触れない)で使う静的ロガー。
    private static let openLogger = Logger(subsystem: "com.phlox.Phlox", category: "SQLiteMessageStore")
    private let logger = Logger(subsystem: "com.phlox.Phlox", category: "SQLiteMessageStore")

    public init(databaseURL: URL, retentionDays: Int = 30) throws {
        var handle: OpaquePointer?
        let path = databaseURL.path(percentEncoded: false)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let openResult = sqlite3_open_v2(path, &handle, flags, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = String(cString: sqlite3_errstr(openResult))
            throw MessageStoreError.openFailed(message)
        }

        do {
            try Self.exec(handle, sql: "PRAGMA journal_mode=WAL;")
            // WAL 有効下での安全な fsync 削減。journal_mode=WAL の後に設定する。
            try Self.exec(handle, sql: "PRAGMA synchronous=NORMAL;")
            try Self.exec(handle, sql: "PRAGMA busy_timeout=3000;")

            let version = try Self.readUserVersion(handle)
            // スキーマ事前状態は「新規 / v1(user_version=1) / 狭窓(v1形テーブル・user_version=0) /
            // 旧狭窓バグを踏んだ第4状態(v1形テーブルのまま user_version=2 確定)」の 4 通り。
            // いずれからでも「列追加(migration) → 索引作成 → user_version 確定」の順序を守る。
            try Self.createSchema(handle)
            // migration の判定は user_version でなくスキーマ形状(列の有無)で行う。version<schemaVersion
            // でゲートすると第4状態(user_version=2・列なし)で列補修がスキップされ、後段の索引作成が
            // "no such column: in_reply_to" で throw して init 失敗(アプリ起動不能)になる。
            // migrateToSchemaVersion2 は messageColumnExists ガードで冪等なので常時実行してよい。
            try Self.migrateToSchemaVersion2(handle)
            // in_reply_to 索引は列補修の後に作る(列より先だと "no such column")。IF NOT EXISTS で冪等。
            // 旧コードが作った索引なしの v2 DB にも後付けするため常に実行する。
            try Self.createInReplyToIndex(handle)
            if version < schemaVersion {
                // 移行がすべて完了した後に user_version を確定する。途中でクラッシュしても
                // user_version は据え置かれ、次回開店で形状ベース migration が再走する(自己修復)。
                try Self.setUserVersion(handle, version: schemaVersion)
            }
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }

        // 保持ポリシー: 開店時に created_at が retentionDays を超えた行を削除する。
        // schema 確立後・索引存在下で実行する。削除失敗は best-effort としてログのみ残し、
        // 開店は継続する(record 中は削除しない)。
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        Self.purgeExpiredMessages(handle, olderThan: cutoff)

        connection = SQLiteConnection(pointer: handle)
    }

    private var db: OpaquePointer? {
        connection.pointer
    }

    public func record(_ message: AgentMessage) async {
        guard let db else { return }

        let sql = """
            INSERT INTO messages (\(MessageColumn.list))
            VALUES (\(MessageColumn.placeholders))
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            logger.error("record: prepare failed for message \(message.id, privacy: .public): \(Self.errorMessage(db), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, MessageColumn.id.bindIndex, message.id.uuidString)
        bindOptionalText(statement, MessageColumn.fromSession.bindIndex, message.fromSession?.rawValue.uuidString)
        bindOptionalText(statement, MessageColumn.fromName.bindIndex, message.fromName)
        bindText(statement, MessageColumn.toSession.bindIndex, message.toSession.rawValue.uuidString)
        bindOptionalText(statement, MessageColumn.toName.bindIndex, message.toName)
        bindText(statement, MessageColumn.text.bindIndex, message.text)
        sqlite3_bind_int(statement, MessageColumn.submit.bindIndex, message.submit ? 1 : 0)
        sqlite3_bind_double(statement, MessageColumn.createdAt.bindIndex, message.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, MessageColumn.delivered.bindIndex, message.delivered ? 1 : 0)
        bindOptionalText(statement, MessageColumn.inReplyTo.bindIndex, message.inReplyTo?.uuidString)

        let stepResult = sqlite3_step(statement)
        if stepResult != SQLITE_DONE {
            // 公開プロトコルが非 throws のため、失敗を検知してログに残す(メッセージは記録されない)
            logger.error("record: insert failed for message \(message.id, privacy: .public) (code \(stepResult)): \(Self.errorMessage(db), privacy: .public)")
        }
    }

    public func recent(limit: Int) async -> [AgentMessage] {
        guard let db else { return [] }

        let clampedLimit = min(max(limit, 1), 500)
        let sql = """
            SELECT \(MessageColumn.list)
            FROM messages
            ORDER BY created_at DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(clampedLimit))

        var messages: [AgentMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let message = Self.message(from: statement) {
                messages.append(message)
            }
        }
        return messages
    }

    public func message(id: UUID) async -> AgentMessage? {
        guard let db else { return nil }

        let sql = """
            SELECT \(MessageColumn.list)
            FROM messages
            WHERE id = ?
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, id.uuidString)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return Self.message(from: statement)
    }

    public func thread(rootID: UUID) async -> [AgentMessage] {
        guard let db else { return [] }

        let sql = """
            SELECT \(MessageColumn.list)
            FROM messages
            WHERE id = ? OR in_reply_to = ?
            ORDER BY created_at ASC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, rootID.uuidString)
        bindText(statement, 2, rootID.uuidString)

        var messages: [AgentMessage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let message = Self.message(from: statement) {
                messages.append(message)
            }
        }
        return messages
    }

    // MARK: - Schema

    private static func createSchema(_ db: OpaquePointer) throws {
        try exec(
            db,
            sql: """
                CREATE TABLE IF NOT EXISTS messages(
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
                CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
                CREATE INDEX IF NOT EXISTS idx_messages_to ON messages(to_session);
                """
        )
    }

    private static func migrateToSchemaVersion2(_ db: OpaquePointer) throws {
        if try !messageColumnExists(db, column: "in_reply_to") {
            try exec(db, sql: "ALTER TABLE messages ADD COLUMN in_reply_to TEXT;")
        }
    }

    /// thread() の `WHERE id=? OR in_reply_to=?` を全表スキャンさせないための索引。
    /// in_reply_to 列が存在する状態(= migration 完了後)でのみ呼ぶこと。IF NOT EXISTS で冪等。
    private static func createInReplyToIndex(_ db: OpaquePointer) throws {
        try exec(db, sql: "CREATE INDEX IF NOT EXISTS idx_messages_in_reply_to ON messages(in_reply_to);")
    }

    /// 開店時の保持ポリシー: cutoff より古い(= 保持期間を超えた)行を削除する。
    /// best-effort — 失敗しても開店は継続する(呼び出し側は throw を受けない)。
    /// 境界: created_at == cutoff(ちょうど保持期間)は「超過」ではないので残す(`<` を使う)。
    private static func purgeExpiredMessages(_ db: OpaquePointer, olderThan cutoff: Date) {
        let sql = "DELETE FROM messages WHERE created_at < ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            openLogger.error("retention: prepare failed: \(errorMessage(db), privacy: .public)")
            return
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            openLogger.error("retention: delete failed (code \(result)): \(errorMessage(db), privacy: .public)")
        }
    }

    private static func messageColumnExists(_ db: OpaquePointer, column: String) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(messages);", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw MessageStoreError.prepareFailed(errorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, 1) == column {
                return true
            }
        }
        return false
    }

    private static func readUserVersion(_ db: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw MessageStoreError.prepareFailed(errorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func setUserVersion(_ db: OpaquePointer, version: Int32) throws {
        try exec(db, sql: "PRAGMA user_version = \(version);")
    }

    // MARK: - Row parsing

    private static func message(from statement: OpaquePointer) -> AgentMessage? {
        guard let idString = columnText(statement, MessageColumn.id.rawValue),
              let id = UUID(uuidString: idString),
              let toSessionString = columnText(statement, MessageColumn.toSession.rawValue),
              let toUUID = UUID(uuidString: toSessionString),
              let text = columnText(statement, MessageColumn.text.rawValue)
        else {
            return nil
        }

        let fromSession: SessionID? = columnText(statement, MessageColumn.fromSession.rawValue).flatMap { UUID(uuidString: $0) }.map { SessionID(rawValue: $0) }
        let fromName = columnText(statement, MessageColumn.fromName.rawValue)
        let toName = columnText(statement, MessageColumn.toName.rawValue)
        let submit = sqlite3_column_int(statement, MessageColumn.submit.rawValue) != 0
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, MessageColumn.createdAt.rawValue))
        let delivered = sqlite3_column_int(statement, MessageColumn.delivered.rawValue) != 0
        let inReplyTo = columnText(statement, MessageColumn.inReplyTo.rawValue).flatMap { UUID(uuidString: $0) }

        return AgentMessage(
            id: id,
            fromSession: fromSession,
            fromName: fromName,
            toSession: SessionID(rawValue: toUUID),
            toName: toName,
            text: text,
            submit: submit,
            createdAt: createdAt,
            delivered: delivered,
            inReplyTo: inReplyTo
        )
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(cString: cString)
    }

    // MARK: - SQLite helpers

    private static func exec(_ db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? Self.errorMessage(db)
            sqlite3_free(errorMessage)
            throw MessageStoreError.execFailed(message)
        }
    }

    private static func errorMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        _ = value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, sqliteTransient)
        }
    }

    private func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            bindText(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
