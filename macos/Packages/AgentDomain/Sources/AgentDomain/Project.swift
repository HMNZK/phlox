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

    /// セッションごとに git worktree を作って隔離するか（task-2 契約・オプトイン）。
    ///
    /// **必ず Optional のままにすること。** `Project` は合成 `Codable` で、`JSONProjectStore` は
    /// フィールドレベルのマイグレーションを持たない（`ProjectsFile.schemaVersion` は書くだけで
    /// 読み込み時に分岐しない）。非 Optional にすると、このキーを持たない旧 `projects.json` の
    /// デコードが失敗し、`JSONFileStore.load()` が `quarantineCorruptFile()` でファイルを
    /// `.corrupt-<ts>` へ退避して `nil` を返す＝アプリ上のプロジェクト一覧が空になる。
    ///
    /// 旧データを読み込むための互換項目。起動・復元の判断には使わない。
    public var worktreeIsolationEnabled: Bool?

    public var directoryURL: URL {
        URL(fileURLWithPath: directoryPath, isDirectory: true)
    }

    public init(
        id: ProjectID = ProjectID(),
        name: String,
        directoryPath: String,
        createdAt: Date,
        isManagedDirectory: Bool,
        worktreeIsolationEnabled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = createdAt
        self.isManagedDirectory = isManagedDirectory
        self.worktreeIsolationEnabled = worktreeIsolationEnabled
    }
}
