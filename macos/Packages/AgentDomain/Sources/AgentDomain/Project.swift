import Foundation

// UI上の「ワークスペース」を内部では Project と呼ぶ。
// 既存の workspace（= per-session CWD）とは別概念。

public struct ProjectID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public struct Project: Identifiable, Hashable, Sendable, Codable {
    public let id: ProjectID
    public var name: String
    public let directoryPath: String
    public let createdAt: Date
    public let isManagedDirectory: Bool

    public var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    public init(
        id: ProjectID = ProjectID(),
        name: String,
        directoryPath: String,
        createdAt: Date,
        isManagedDirectory: Bool
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.isManagedDirectory = isManagedDirectory
    }
}
