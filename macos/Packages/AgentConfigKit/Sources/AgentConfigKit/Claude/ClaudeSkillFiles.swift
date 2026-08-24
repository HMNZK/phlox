import Foundation

/// Claude Code の skill 1件（`skills/<name>/SKILL.md`）。
public struct ClaudeSkill: Sendable, Equatable, Identifiable {
    public let scope: AgentMemoryFile.Scope
    /// ディレクトリ名（`skills/<directoryName>/SKILL.md`）。
    public let directoryName: String
    /// frontmatter の `name`。無ければ `directoryName`。
    public let name: String
    public let description: String
    /// `SKILL.md` の絶対パス。
    public let skillFileURL: URL
    /// skill ディレクトリの絶対パス。
    public let directoryURL: URL
    /// 画面に出す短いパス。
    public let displayPath: String

    public var id: String { skillFileURL.path }

    public init(
        scope: AgentMemoryFile.Scope,
        directoryName: String,
        name: String,
        description: String,
        skillFileURL: URL,
        directoryURL: URL,
        displayPath: String
    ) {
        self.scope = scope
        self.directoryName = directoryName
        self.name = name
        self.description = description
        self.skillFileURL = skillFileURL
        self.directoryURL = directoryURL
        self.displayPath = displayPath
    }
}

/// SKILL.md 先頭の YAML frontmatter を依存なしで読む。
public enum ClaudeSkillFrontmatterParsing: Sendable {
    /// `---` で挟まれた先頭ブロックから `key: value` を拾う。
    public static func parse(from markdown: String) -> [String: String] {
        let normalized = markdown.hasPrefix("\u{FEFF}")
            ? String(markdown.dropFirst())
            : markdown
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }

        var endIndex: Int?
        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = index
                break
            }
        }
        guard let endIndex else { return [:] }

        var result: [String: String] = [:]
        for line in lines[1..<endIndex] {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            value = stripQuotes(from: value)
            result[key] = value
        }
        return result
    }

    private static func stripQuotes(from value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first!
        let last = value.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

/// Claude Code の skill ディレクトリの探索・読み書き・削除。
public struct ClaudeSkillFiles: Sendable {
    private let paths: ClaudeConfigPaths

    public init(paths: ClaudeConfigPaths) {
        self.paths = paths
    }

    /// `FileManager` は `Sendable` ではないので保持せず、都度 `default` を使う。
    private var fileManager: FileManager { .default }

    /// ユーザー用と（あれば）プロジェクト用の skill を列挙する。
    /// `SKILL.md` が無いディレクトリは無視する。
    public func discover(projectDirectory: URL?) -> [ClaudeSkill] {
        var skills: [ClaudeSkill] = []
        skills.append(contentsOf: discover(in: paths.userSkillsDirectory, scope: .user, displayPrefix: "~/.claude/skills"))
        if let projectDirectory {
            let directory = paths.projectSkillsDirectory(projectDirectory: projectDirectory)
            let prefix = "\(projectDirectory.lastPathComponent)/.claude/skills"
            skills.append(contentsOf: discover(in: directory, scope: .project, displayPrefix: prefix))
        }
        return skills.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func read(_ skill: ClaudeSkill) throws -> String {
        guard fileManager.fileExists(atPath: skill.skillFileURL.path) else { return "" }
        return try String(contentsOf: skill.skillFileURL, encoding: .utf8)
    }

    public func write(_ text: String, to skill: ClaudeSkill) throws {
        let directory = skill.directoryURL
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(text.utf8).write(to: skill.skillFileURL, options: .atomic)
    }

    /// skill ディレクトリごとゴミ箱へ移す（完全削除はしない）。
    public func delete(_ skill: ClaudeSkill) throws {
        guard fileManager.fileExists(atPath: skill.directoryURL.path) else { return }
        var trashedURL: NSURL?
        try fileManager.trashItem(at: skill.directoryURL, resultingItemURL: &trashedURL)
    }

    // MARK: - 内部

    private func discover(
        in root: URL,
        scope: AgentMemoryFile.Scope,
        displayPrefix: String
    ) -> [ClaudeSkill] {
        guard fileManager.fileExists(atPath: root.path),
              let entries = try? fileManager.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        var skills: [ClaudeSkill] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let skillFileURL = entry.appendingPathComponent("SKILL.md", isDirectory: false)
            guard fileManager.fileExists(atPath: skillFileURL.path) else { continue }

            let directoryName = entry.lastPathComponent
            let frontmatter = (try? String(contentsOf: skillFileURL, encoding: .utf8))
                .map(ClaudeSkillFrontmatterParsing.parse(from:)) ?? [:]
            let name = frontmatter["name"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? directoryName
            let description = frontmatter["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            skills.append(
                ClaudeSkill(
                    scope: scope,
                    directoryName: directoryName,
                    name: name,
                    description: description,
                    skillFileURL: skillFileURL,
                    directoryURL: entry,
                    displayPath: "\(displayPrefix)/\(directoryName)/SKILL.md"
                )
            )
        }
        return skills
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
