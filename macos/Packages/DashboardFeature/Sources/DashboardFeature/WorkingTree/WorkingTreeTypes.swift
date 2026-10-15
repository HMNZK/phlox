import Foundation

public struct WorkingTreeChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case modified
        case added
        case deleted
        case untracked
        case renamed
    }

    public let path: String
    public let kind: Kind
    public let isBinary: Bool
    public let originalPath: String?

    public init(path: String, kind: Kind, isBinary: Bool, originalPath: String? = nil) {
        self.path = path
        self.kind = kind
        self.isBinary = isBinary
        self.originalPath = originalPath
    }
}

public enum WorkingTreeDetail: Equatable, Sendable {
    case diff(String)
    case untrackedContent(String)
    case binary
}

public enum WorkingTreeSaveOutcome: Equatable, Sendable {
    case saved
    case conflict
}

/// 差分の比較元。作業ツリーは index と、ステージ済みは HEAD と比較する。
public enum WorkingTreeSource: Equatable, Sendable, Hashable {
    case worktree
    case staged
    case commit(String)
    case stash(id: String, name: String)

    var isHistory: Bool {
        switch self { case .commit, .stash: true; default: false }
    }

    var revision: String? {
        switch self { case .commit(let id), .stash(let id, _): id; default: nil }
    }

    public var rawValue: String {
        switch self {
        case .worktree: "worktree"
        case .staged: "staged"
        case .commit(let id): "commit-" + id
        case .stash(let id, _): "stash-" + id
        }
    }
}

public struct GitChangeSelection: Equatable, Sendable, Hashable {
    public let path: String
    public let source: WorkingTreeSource

    public init(path: String, source: WorkingTreeSource) {
        self.path = path
        self.source = source
    }
}
