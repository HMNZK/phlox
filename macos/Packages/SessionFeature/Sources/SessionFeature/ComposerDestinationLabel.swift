import Foundation

public enum ComposerDestinationLabel {
    public enum Destination: Equatable, Sendable {
        case conversation(projectName: String?, taskName: String)
        case parentSession(projectName: String?, taskName: String?)
    }

    public static func text(
        for destination: Destination,
        hasDestination: Bool,
        isReadyForInput: Bool,
        hasContent: Bool
    ) -> String {
        let base = baseText(for: destination)
        if !hasDestination {
            return base + " — 送信不可（送信先がありません）"
        }
        if !isReadyForInput {
            return base + " — 送信不可（入力を受け付けられません）"
        }
        if !hasContent {
            return base + " — 送信不可（メッセージを入力してください）"
        }
        return base
    }

    private static func baseText(for destination: Destination) -> String {
        switch destination {
        case .conversation(let projectName, let taskName):
            return "\(displayProjectName(projectName)) / \(displayTaskName(taskName))"
        case .parentSession(let projectName, let taskName):
            guard let taskName = normalizedName(taskName) else {
                return "親セッションへの送信"
            }
            return "\(displayProjectName(projectName)) / \(taskName) — 親セッションへの送信"
        }
    }

    private static func displayProjectName(_ raw: String?) -> String {
        normalizedName(raw) ?? "プロジェクト名不明"
    }

    private static func displayTaskName(_ raw: String) -> String {
        normalizedName(raw) ?? "作業名不明"
    }

    private static func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
