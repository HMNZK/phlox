import Foundation

public struct ChatFilePatch: Equatable, Sendable {
    public let path: String
    public let diff: String
    public let kind: String?

    public init(path: String, diff: String, kind: String?) {
        self.path = path
        self.diff = diff
        self.kind = kind
    }
}

public enum ChatFileChangePresentation {
    public struct Counts: Equatable, Sendable {
        public let additions: Int
        public let deletions: Int

        public init(additions: Int, deletions: Int) {
            self.additions = additions
            self.deletions = deletions
        }
    }

    public static func verb(for kind: String?) -> String {
        let normalized = kind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.contains("edit") { return "編集済み" }
        if normalized.contains("write") || normalized.contains("create") { return "作成済み" }
        if normalized.contains("delete") { return "削除済み" }
        return "変更済み"
    }

    public static func counts(for changes: [ChatFilePatch]) -> Counts {
        let lines = changes.flatMap { ChatDiffClassifier.classify($0.diff) }
        return Counts(
            additions: lines.count { $0.kind == .addition },
            deletions: lines.count { $0.kind == .deletion }
        )
    }

    public static func title(for changes: [ChatFilePatch]) -> String {
        let verb = verb(for: changes.first?.kind)
        if changes.count == 1, let path = changes.first?.path {
            return "\(verb) \(filename(from: path))"
        }
        return "\(verb) \(changes.count) 件のファイル"
    }

    private static func filename(from path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
    }
}
