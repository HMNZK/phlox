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

    public init(path: String, kind: Kind, isBinary: Bool) {
        self.path = path
        self.kind = kind
        self.isBinary = isBinary
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
