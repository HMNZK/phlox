import Foundation
import AgentDomain

public struct HistoryEntryPresentation: Equatable, Sendable {
    public let title: String
    public let fullTitle: String
    public let projectName: String
    public let projectPath: String?
    public let lastUsedAt: Date?

    /// ponytail: 定型文除外は接頭辞 `<` と `Base directory for this skill:` だけ。
    /// 拡張には具体例と固定テストが要る。
    public init(
        entry: ClaudeSessionHistoryEntry,
        workingDirectory: String?
    ) {
        var derived: DerivedSessionTitle?
        for material in entry.titleUserMessages ?? [entry.preview] {
            if Self.isBoilerplatePrefix(material) {
                continue
            }
            if let candidate = SessionTitleDeriver.derive(from: material) {
                derived = candidate
                break
            }
        }
        if derived == nil,
           let summary = entry.titleSummary,
           !Self.isBoilerplatePrefix(summary)
        {
            derived = SessionTitleDeriver.derive(from: summary)
        }
        title = derived?.title ?? "作業名なし"
        fullTitle = derived?.fullTitle ?? "作業名なし"

        if let workingDirectory,
           !workingDirectory.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) })
        {
            projectName = Self.projectName(from: workingDirectory)
            projectPath = workingDirectory
        } else {
            projectName = "プロジェクト不明"
            projectPath = nil
        }

        lastUsedAt = entry.lastModified == .distantPast ? nil : entry.lastModified
    }

    private static func isBoilerplatePrefix(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<") || trimmed.hasPrefix("Base directory for this skill:")
    }

    private static func projectName(from workingDirectory: String) -> String {
        var nameSource = workingDirectory
        while nameSource.count > 1, nameSource.hasSuffix("/") {
            nameSource.removeLast()
        }
        if nameSource == "/" {
            return "/"
        }
        if let slash = nameSource.lastIndex(of: "/") {
            let name = String(nameSource[nameSource.index(after: slash)...])
            return name.isEmpty ? "/" : name
        }
        return nameSource
    }
}
