import Foundation
import SessionFeature
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Codex の state SQLite を優先し、利用できない環境では rollout JSONL から履歴を読む。
struct CodexSessionHistoryDiscovery: Sendable {
    static let maxSessionMetaBytes = 16 * 1024
    static let maxBytesPerFile = 512 * 1024

    let codexHome: URL
    let sessionsRoot: URL

    init(codexHome: URL) {
        self.codexHome = codexHome
        sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
    }

    func entries(
        forWorkingDirectory workingDirectory: String,
        limit: Int,
        onScan: (@Sendable (URL) -> Void)? = nil,
        onRead: (@Sendable (Int) -> Void)? = nil
    ) -> [ClaudeSessionHistoryEntry] {
        guard limit > 0 else { return [] }
        let normalizedCWD = CodexSessionDiscovery.normalizedPath(workingDirectory)
        if let databaseEntries = databaseEntries(
            forWorkingDirectory: workingDirectory,
            normalizedCWD: normalizedCWD,
            limit: limit
        ) {
            return databaseEntries
        }
        var result: [ClaudeSessionHistoryEntry] = []

        for candidate in rolloutFiles() {
            guard let scan = scan(
                candidate.url,
                matchingCWD: normalizedCWD,
                onScan: onScan,
                onRead: onRead
            ),
                  scan.cwd.map(CodexSessionDiscovery.normalizedPath) == normalizedCWD,
                  let preview = scan.firstUserText,
                  !preview.isEmpty else {
                continue
            }
            let sessionID = scan.sessionID ?? CodexSessionDiscovery.uuidFromRolloutFilename(candidate.url.lastPathComponent)
            guard let sessionID else { continue }
            result.append(
                ClaudeSessionHistoryEntry(
                    sessionID: sessionID,
                    preview: Self.normalizedPreview(preview),
                    firstUserAt: scan.firstUserAt,
                    lastModified: candidate.modified,
                    gitBranch: nil,
                    fileURL: candidate.url
                )
            )
            if result.count == limit { break }
        }

        return result
    }

    private func databaseEntries(
        forWorkingDirectory workingDirectory: String,
        normalizedCWD: String,
        limit: Int
    ) -> [ClaudeSessionHistoryEntry]? {
        guard let databaseURL = stateDatabaseURL() else { return nil }
        guard let entries = queryDatabase(databaseURL: databaseURL, cwd: normalizedCWD, limit: limit) else {
            return nil
        }
        guard entries.isEmpty, workingDirectory != normalizedCWD else { return entries }
        return queryDatabase(databaseURL: databaseURL, cwd: workingDirectory, limit: limit)
    }

    private func stateDatabaseURL() -> URL? {
        let fileManager = FileManager.default
        let preferred = codexHome.appendingPathComponent("state_5.sqlite")
        if (try? preferred.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return preferred
        }
        guard let files = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files
            .compactMap { url -> (url: URL, number: Int)? in
                let stem = url.deletingPathExtension().lastPathComponent
                guard url.pathExtension == "sqlite",
                      stem.hasPrefix("state_"),
                      let number = Int(stem.dropFirst("state_".count)),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                return (url, number)
            }
            .sorted { $0.number == $1.number ? $0.url.path < $1.url.path : $0.number > $1.number }
            .first?.url
    }

    private func queryDatabase(
        databaseURL: URL,
        cwd: String,
        limit: Int
    ) -> [ClaudeSessionHistoryEntry]? {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path(percentEncoded: false),
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close_v2(database) }
            return nil
        }
        defer { sqlite3_close_v2(database) }

        let sql = """
        SELECT id, rollout_path, preview, first_user_message, updated_at_ms
        FROM threads
        WHERE archived = 0 AND cwd = ?
          AND (preview <> '' OR first_user_message <> '')
        ORDER BY updated_at_ms DESC, id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard cwd.withCString({ sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient) }) == SQLITE_OK,
              sqlite3_bind_int(statement, 2, Int32(limit)) == SQLITE_OK else {
            return nil
        }

        var entries: [ClaudeSessionHistoryEntry] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return entries }
            guard step == SQLITE_ROW,
                  let sessionID = Self.databaseString(statement, column: 0),
                  let rolloutPath = Self.databaseString(statement, column: 1),
                  !sessionID.isEmpty,
                  !rolloutPath.isEmpty else {
                if step == SQLITE_ROW { continue }
                return nil
            }
            let preview = Self.databaseString(statement, column: 2)
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? Self.databaseString(statement, column: 3)
            guard let preview, !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let updatedAt: Date
            if sqlite3_column_type(statement, 4) == SQLITE_NULL {
                updatedAt = .distantPast
            } else {
                updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1_000)
            }
            entries.append(
                ClaudeSessionHistoryEntry(
                    sessionID: sessionID,
                    preview: Self.normalizedPreview(preview),
                    firstUserAt: nil,
                    lastModified: updatedAt,
                    gitBranch: nil,
                    fileURL: URL(fileURLWithPath: rolloutPath)
                )
            )
        }
    }

    private static func databaseString(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private struct RolloutFile {
        let url: URL
        let modified: Date
    }

    private func rolloutFiles() -> [RolloutFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return RolloutFile(url: url, modified: values.contentModificationDate ?? .distantPast)
        }.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.url.path < $1.url.path
        }
    }

    private struct Scan {
        var sessionID: String?
        var cwd: String?
        var firstUserText: String?
        var firstUserAt: Date?
    }

    private func scan(
        _ fileURL: URL,
        matchingCWD: String,
        onScan: (@Sendable (URL) -> Void)?,
        onRead: (@Sendable (Int) -> Void)?
    ) -> Scan? {
        onScan?(fileURL)
        guard let prefix = Self.read(
            fileURL,
            maxBytes: Self.maxSessionMetaBytes,
            onRead: onRead
        ),
              let metadata = Self.sessionMeta(from: prefix) else {
            return nil
        }
        guard metadata.cwd.map(CodexSessionDiscovery.normalizedPath) == matchingCWD else {
            return metadata
        }
        guard let data = Self.read(fileURL, maxBytes: Self.maxBytesPerFile, onRead: onRead), !data.isEmpty else {
            return metadata
        }
        var scan = metadata
        for (index, line) in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).enumerated() {
            guard let object = Self.object(from: String(line)) else { continue }
            let timestamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp)
            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                scan.sessionID = payload["id"] as? String ?? payload["session_id"] as? String
                scan.cwd = payload["cwd"] as? String
            }
            if scan.firstUserText == nil,
               let text = Self.messageText(in: object, role: "user"),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scan.firstUserText = text
                scan.firstUserAt = scan.firstUserAt ?? timestamp
            }
            if index > 200 { break }
        }
        return scan.cwd == nil ? nil : scan
    }

    private static func sessionMeta(from data: Data) -> Scan? {
        guard let line = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .first,
              let object = object(from: String(line)),
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        return Scan(
            sessionID: payload["id"] as? String ?? payload["session_id"] as? String,
            cwd: payload["cwd"] as? String,
            firstUserText: nil,
            firstUserAt: nil
        )
    }

    static func loadTranscript(fileURL: URL, maxItems: Int) -> [ChatItem] {
        guard maxItems > 0,
              let data = read(fileURL, maxBytes: 4 * 1024 * 1024) else { return [] }
        var items: [ChatItem] = []
        for (index, line) in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).enumerated() {
            guard let object = object(from: String(line)),
                  let role = messageRole(in: object),
                  let text = messageText(in: object, role: role),
                  !text.isEmpty else { continue }
            let id = messageID(in: object) ?? "codex-" + role + "-" + String(index)
            let timestamp = (object["timestamp"] as? String).flatMap(parseTimestamp) ?? .distantPast
            switch role {
            case "user": items.append(.userMessage(id: id, text: text, timestamp: timestamp))
            case "assistant": items.append(.agentMessage(id: id, text: text, timestamp: timestamp))
            default: continue
            }
            if items.count >= maxItems { break }
        }
        return items
    }

    private static func messageRole(in object: [String: Any]) -> String? {
        if object["type"] as? String == "response_item",
           let payload = object["payload"] as? [String: Any],
           payload["type"] as? String == "message" {
            return payload["role"] as? String
        }
        if object["type"] as? String == "event_msg",
           let payload = object["payload"] as? [String: Any] {
            switch payload["type"] as? String {
            case "user_message": return "user"
            case "agent_message", "assistant_message": return "assistant"
            default: return nil
            }
        }
        return nil
    }

    private static func messageID(in object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        return payload["id"] as? String
    }

    private static func messageText(in object: [String: Any], role: String) -> String? {
        let payload = object["payload"] as? [String: Any]
        if object["type"] as? String == "event_msg", let payload {
            if let message = payload["message"] as? String { return message }
            if let content = payload["content"] { return text(from: content, role: role) }
        }
        guard let payload,
              let content = payload["content"] else { return nil }
        return text(from: content, role: role)
    }

    private static func text(from value: Any, role: String) -> String? {
        if let string = value as? String { return string }
        guard let blocks = value as? [[String: Any]] else { return nil }
        let allowed = role == "user" ? Set(["input_text", "text"]) : Set(["output_text", "text"])
        let texts = blocks.compactMap { block -> String? in
            guard let type = block["type"] as? String, allowed.contains(type) else { return nil }
            return block["text"] as? String
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static func object(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func read(
        _ fileURL: URL,
        maxBytes: Int,
        onRead: (@Sendable (Int) -> Void)? = nil
    ) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        onRead?(data.count)
        return data
    }

    private static func normalizedPreview(_ text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.count <= 120 ? collapsed : String(collapsed.prefix(120))
    }

    private static func parseTimestamp(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

struct CodexSessionTranscriptLoader: Sendable {
    func load(fileURL: URL, maxItems: Int) -> [ChatItem] {
        CodexSessionHistoryDiscovery.loadTranscript(fileURL: fileURL, maxItems: maxItems)
    }
}
