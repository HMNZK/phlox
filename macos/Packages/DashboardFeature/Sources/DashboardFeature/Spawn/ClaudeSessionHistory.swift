import Foundation
import SessionFeature

// task-3 契約の PM スタブ。API 表面は受け入れテスト
// ClaudeSessionHistoryAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-3.md

/// 改行バイト `0x0A` でバイト列を分割してから各行を UTF-8 decode する。
/// `read(upToCount:)` のバイト境界がマルチバイト文字を割ってもデータを喪失しない。
private struct JSONLByteLineReader {
    private let handle: FileHandle
    private let chunkSize: Int
    private var remainder = Data()
    private(set) var bytesConsumed = 0

    init(handle: FileHandle, chunkSize: Int = 16_384) {
        self.handle = handle
        self.chunkSize = chunkSize
    }

    mutating func nextLine() -> String? {
        while true {
            if let newlineIndex = remainder.firstIndex(of: 0x0A) {
                let lineData = remainder[..<newlineIndex]
                remainder = Data(remainder[(newlineIndex + 1)...])
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                return line
            }

            guard let chunkData = try? handle.read(upToCount: chunkSize), !chunkData.isEmpty else {
                guard !remainder.isEmpty else { return nil }
                let tail = remainder
                remainder = Data()
                return String(data: tail, encoding: .utf8)
            }
            bytesConsumed += chunkData.count
            remainder.append(chunkData)
        }
    }
}

// ClaudeSessionHistoryEntry（履歴 1 件のメタ情報）は Session/ClaudeSessionHistoryEntry.swift へ
// 移設した（R1・task-26: Session ↔ Spawn 循環の切断。Session 側が消費するデータ型のため下層へ降ろす）。

/// Claude Code の履歴 JSONL（`~/.claude/projects/<dir>/<session-uuid>.jsonl`）を走査する。
struct ClaudeSessionHistoryDiscovery: Sendable {
    static let maxLinesPerFile = 200
    static let maxBytesPerFile = 256 * 1024

    let projectsRoot: URL

    init(projectsRoot: URL) {
        self.projectsRoot = projectsRoot
    }

    /// cwd → プロジェクトディレクトリ名（英数字以外をすべて `-` に置換）。
    static func projectDirectoryName(forWorkingDirectory workingDirectory: String) -> String {
        workingDirectory.map { character in
            Self.isAsciiAlphanumeric(character) ? String(character) : "-"
        }.joined()
    }

    private static func isAsciiAlphanumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        let value = scalar.value
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    /// 対象 cwd の履歴一覧（mtime 降順・limit 件）。
    func entries(forWorkingDirectory workingDirectory: String, limit: Int) -> [ClaudeSessionHistoryEntry] {
        let projectDir = projectsRoot.appendingPathComponent(
            Self.projectDirectoryName(forWorkingDirectory: workingDirectory),
            isDirectory: true
        )

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var discovered: [ClaudeSessionHistoryEntry] = []

        for fileURL in contents {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                continue
            }

            let scan = Self.scanFile(at: fileURL)
            guard !scan.isSidechainFile else { continue }
            guard let firstUser = scan.firstUserLine else { continue }

            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            let lastModified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            discovered.append(
                ClaudeSessionHistoryEntry(
                    sessionID: sessionID,
                    preview: Self.normalizedPreview(from: firstUser.text),
                    firstUserAt: firstUser.timestamp,
                    lastModified: lastModified,
                    gitBranch: firstUser.gitBranch,
                    fileURL: fileURL
                )
            )
        }

        discovered.sort { $0.lastModified > $1.lastModified }
        if limit < discovered.count {
            return Array(discovered.prefix(limit))
        }
        return discovered
    }

    // MARK: - File scan

    private struct UserLineInfo {
        let text: String
        let timestamp: Date?
        let gitBranch: String?
    }

    private struct FileScanResult {
        let isSidechainFile: Bool
        let firstUserLine: UserLineInfo?
    }

    private static func scanFile(at fileURL: URL) -> FileScanResult {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return FileScanResult(isSidechainFile: false, firstUserLine: nil)
        }
        defer { try? handle.close() }

        var isSidechainFile = false
        var firstUserLine: UserLineInfo?
        var lineCount = 0
        var reader = JSONLByteLineReader(handle: handle)

        while lineCount < maxLinesPerFile, reader.bytesConsumed < maxBytesPerFile {
            guard let line = reader.nextLine() else { break }
            processScannedLine(
                line,
                lineCount: &lineCount,
                isSidechainFile: &isSidechainFile,
                firstUserLine: &firstUserLine
            )
        }

        return FileScanResult(isSidechainFile: isSidechainFile, firstUserLine: firstUserLine)
    }

    private static func processScannedLine(
        _ line: String,
        lineCount: inout Int,
        isSidechainFile: inout Bool,
        firstUserLine: inout UserLineInfo?
    ) {
        lineCount += 1
        guard let parsed = parseLine(line) else { return }

        if parsed.isSidechain == true {
            isSidechainFile = true
        }

        if firstUserLine == nil,
           parsed.type == "user",
           let userText = extractUserText(from: parsed),
           !userText.hasPrefix("<") {
            firstUserLine = UserLineInfo(
                text: userText,
                timestamp: parsed.timestamp.flatMap(parseTimestamp),
                gitBranch: parsed.gitBranch
            )
        }
    }

    private static func normalizedPreview(from text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= 120 {
            return collapsed
        }
        return String(collapsed.prefix(120))
    }
}

/// 履歴 JSONL からユーザー/エージェントのテキスト発言だけを ChatItem に写像する。
struct ClaudeSessionTranscriptLoader: Sendable {
    init() {}

    /// 出現順を保った末尾 maxItems 件。
    func load(fileURL: URL, maxItems: Int) -> [ChatItem] {
        guard maxItems > 0 else { return [] }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        var items: [ChatItem] = []
        var lineIndex = 0
        var reader = JSONLByteLineReader(handle: handle)

        while let line = reader.nextLine() {
            appendChatItem(from: line, lineIndex: lineIndex, into: &items)
            lineIndex += 1
        }

        if items.count <= maxItems {
            return items
        }
        return Array(items.suffix(maxItems))
    }

    private func appendChatItem(from line: String, lineIndex: Int, into items: inout [ChatItem]) {
        guard let parsed = ClaudeSessionHistoryDiscovery.parseLine(line) else { return }

        switch parsed.type {
        case "user":
            guard let text = ClaudeSessionHistoryDiscovery.extractUserText(from: parsed),
                  !text.hasPrefix("<") else {
                return
            }
            let id = parsed.uuid ?? "user-\(lineIndex)"
            let timestamp = parsed.timestamp.flatMap(ClaudeSessionHistoryDiscovery.parseTimestamp) ?? .distantPast
            items.append(.userMessage(id: id, text: text, timestamp: timestamp))

        case "assistant":
            guard let text = ClaudeSessionHistoryDiscovery.extractAssistantText(from: parsed), !text.isEmpty else {
                return
            }
            let id = parsed.uuid ?? "assistant-\(lineIndex)"
            let timestamp = parsed.timestamp.flatMap(ClaudeSessionHistoryDiscovery.parseTimestamp) ?? .distantPast
            items.append(.agentMessage(id: id, text: text, timestamp: timestamp))

        default:
            break
        }
    }
}

// MARK: - Shared JSONL parsing

extension ClaudeSessionHistoryDiscovery {
    struct ParsedLine {
        let type: String?
        let message: ParsedMessage?
        let uuid: String?
        let timestamp: String?
        let gitBranch: String?
        let isSidechain: Bool?
    }

    struct ParsedMessage {
        let content: ParsedContent?
    }

    enum ParsedContent {
        case string(String)
        case blocks([ParsedContentBlock])
    }

    struct ParsedContentBlock {
        let type: String?
        let text: String?
    }

    static func parseLine(_ line: String) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let message: ParsedMessage?
        if let messageObject = json["message"] as? [String: Any] {
            let content: ParsedContent?
            if let stringContent = messageObject["content"] as? String {
                content = .string(stringContent)
            } else if let blocks = messageObject["content"] as? [[String: Any]] {
                content = .blocks(
                    blocks.map { block in
                        ParsedContentBlock(
                            type: block["type"] as? String,
                            text: block["text"] as? String
                        )
                    }
                )
            } else {
                content = nil
            }
            message = ParsedMessage(content: content)
        } else {
            message = nil
        }

        return ParsedLine(
            type: json["type"] as? String,
            message: message,
            uuid: json["uuid"] as? String,
            timestamp: json["timestamp"] as? String,
            gitBranch: json["gitBranch"] as? String,
            isSidechain: json["isSidechain"] as? Bool
        )
    }

    static func extractUserText(from line: ParsedLine) -> String? {
        guard line.type == "user" else { return nil }
        return extractTextContent(from: line.message?.content)
    }

    static func extractAssistantText(from line: ParsedLine) -> String? {
        guard line.type == "assistant" else { return nil }
        guard case .blocks(let blocks) = line.message?.content else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard block.type == "text", let text = block.text, !text.isEmpty else { return nil }
            return text
        }
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: "\n")
    }

    private static func extractTextContent(from content: ParsedContent?) -> String? {
        switch content {
        case .string(let text):
            return text.isEmpty ? nil : text
        case .blocks(let blocks):
            let texts = blocks.compactMap { block -> String? in
                guard block.type == "text", let text = block.text, !text.isEmpty else { return nil }
                return text
            }
            guard !texts.isEmpty else { return nil }
            return texts.joined(separator: "\n")
        case nil:
            return nil
        }
    }

    static func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}
