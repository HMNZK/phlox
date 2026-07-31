import Foundation

private enum WorkingTreeServiceError: Error {
    case notImplemented
}

/// ワーキングツリー API の公開面を凍結するためのスタブ。
public actor WorkingTreeService {
    public init(repositoryRoot: URL) {}

    public func isGitRepository() -> Bool {
        false
    }

    public func changes() throws -> [WorkingTreeChange] {
        []
    }

    public func detail(for path: String) throws -> WorkingTreeDetail {
        .binary
    }

    public func fileContents(_ path: String) throws -> String {
        ""
    }

    public func save(
        path: String,
        content: String,
        expectedDiskContent: String?
    ) throws -> WorkingTreeSaveOutcome {
        throw WorkingTreeServiceError.notImplemented
    }
}
