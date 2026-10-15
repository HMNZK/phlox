import Foundation
import Observation
import AgentDomain
import SessionFeature

@MainActor @Observable
final class GitDetailLoader {
    private(set) var detail: WorkingTreeDetail?
    private(set) var error: String?
    private var path: String?
    private var generation = 0

    func clear() {
        generation &+= 1
        path = nil
        detail = nil
        error = nil
    }

    func load(path: String, fetch: (String) async throws -> WorkingTreeDetail) async {
        clear()
        self.path = path
        let request = generation
        do {
            let result = try await fetch(path)
            guard !Task.isCancelled, self.path == path, generation == request else { return }
            detail = result
        } catch {
            guard !Task.isCancelled, self.path == path, generation == request else { return }
            self.error = error.localizedDescription
        }
    }
}

struct WorkingTreeLineCount: Equatable, Sendable {
    var added: Int
    var deleted: Int
}

struct WorkingTreeSnapshot: Sendable {
    var branch: String
    var changes: [WorkingTreeChange]
    var lineCounts: [String: WorkingTreeLineCount]
}

/// 表示・更新規則。一覧の正本は EditorPanelViewModel。
enum GitTabPolicy {
    @MainActor
    static func turnCompletions(sessions: [SessionNode], projectID: ProjectID?) -> [SessionID: Date] {
        guard let projectID else { return [:] }
        return Dictionary(uniqueKeysWithValues: sessions.filter { $0.projectID == projectID }
            .compactMap { node in node.controllable.lastTurnCompletedAt.map { (node.id, $0) } })
    }

    @MainActor
    static func refreshAfterTurnCompletions(old: [SessionID: Date], new: [SessionID: Date], model: EditorPanelViewModel) async {
        guard new.contains(where: { id, date in old[id] != date }) else { return }
        await model.refresh()
    }

    static let previewLimit = 60
    static let lineNumberWidth = 300.0
    static func showsLineNumbers(width: Double) -> Bool { width >= lineNumberWidth }

    static func letter(_ kind: WorkingTreeChange.Kind) -> String {
        switch kind {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "U"
        }
    }

    static func kindKey(_ kind: WorkingTreeChange.Kind) -> String {
        switch kind {
        case .added: "追加"
        case .modified: "変更"
        case .deleted: "削除"
        case .renamed: "名前変更"
        case .untracked: "未追跡"
        }
    }

    static func newPaths(previous: Set<String>?, changes: [WorkingTreeChange]) -> Set<String> {
        guard let previous else { return [] }
        return Set(changes.map(\.path)).subtracting(previous)
    }

    enum RefreshEvent: Equatable {
        case shown, foreground, manual
        case fileChanged(root: String)
        case turnEnded(projectMatches: Bool)
    }

    static func shouldRefresh(_ event: RefreshEvent, projectRoot: String?) -> Bool {
        guard let projectRoot else { return false }
        switch event {
        case .shown, .foreground, .manual: return true
        case .turnEnded(let matches): return matches
        case .fileChanged(let root):
            let project = URL(fileURLWithPath: projectRoot).standardizedFileURL.resolvingSymlinksInPath().path
            let changed = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
            return project == changed || project.hasPrefix(changed + "/") || changed.hasPrefix(project + "/")
        }
    }

    enum State: Equatable { case loading, noProject, notRepository, clean, failed(String), changes }

    static func state(list: EditorPanelViewModel.ListState, refreshing: Bool, error: String?, count: Int) -> State {
        if refreshing && count == 0 { return .loading }
        if let error { return .failed(error) }
        switch list {
        case .noProject: return .noProject
        case .notARepository: return .notRepository
        case .ready: return count == 0 ? .clean : .changes
        }
    }
}

struct GitPreviewLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case context, added, deleted, hunk }
    var kind: Kind
    var number: Int?
    var text: String
    var sign: String {
        switch kind { case .added: "+"; case .deleted: "−"; default: "" }
    }
}

struct GitPreview: Equatable, Sendable {
    var lines: [GitPreviewLine]
    var remaining: Int

    static func make(_ detail: WorkingTreeDetail) -> GitPreview {
        var lines: [GitPreviewLine] = []
        switch detail {
        case .binary: break
        case .untrackedContent(let text):
            let content = textLines(text)
            if !content.isEmpty { lines.append(.init(kind: .hunk, number: nil, text: "@@ -0,0 +1,\(content.count) @@")) }
            lines += content.enumerated().map { .init(kind: .added, number: $0.offset + 1, text: $0.element) }
        case .diff(let text):
            var old = 0, new = 0
            var inHunk = false
            for line in textLines(text) {
                if line.hasPrefix("diff --git ") {
                    inHunk = false
                } else if line.hasPrefix("@@") {
                    inHunk = true
                    let parts = line.split(separator: " ")
                    if parts.count >= 3 {
                        old = Int(parts[1].dropFirst().split(separator: ",")[0]) ?? 0
                        new = Int(parts[2].dropFirst().split(separator: ",")[0]) ?? 0
                    }
                    lines.append(.init(kind: .hunk, number: nil, text: line))
                } else if !inHunk {
                    continue
                } else if line.hasPrefix("+") {
                    lines.append(.init(kind: .added, number: new, text: String(line.dropFirst()))); new += 1
                } else if line.hasPrefix("-") {
                    lines.append(.init(kind: .deleted, number: old, text: String(line.dropFirst()))); old += 1
                } else if line.hasPrefix(" ") {
                    lines.append(.init(kind: .context, number: new, text: String(line.dropFirst()))); old += 1; new += 1
                } else if line.hasPrefix("\\") {
                    lines.append(.init(kind: .hunk, number: nil, text: line))
                }
            }
        }
        return .init(lines: Array(lines.prefix(GitTabPolicy.previewLimit)), remaining: max(0, lines.count - GitTabPolicy.previewLimit))
    }

    static func textLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
