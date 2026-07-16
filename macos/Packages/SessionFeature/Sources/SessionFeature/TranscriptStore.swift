import Foundation
import AgentDomain
import StructuredChatKit

public protocol TranscriptStore: Sendable {
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem]
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws
    /// 保存済み転写を `items` で完全に置換する（リバート時の切り詰め結果を反映するため）。
    /// upsert がマージ（追加・更新）なのに対し、こちらは削除も含む置換なので巻き戻しに使う。
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws
    func loadTurnUsageSnapshot(for sessionID: SessionID) async throws -> TurnUsage?
    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws
}

public extension TranscriptStore {
    func loadTurnUsageSnapshot(for sessionID: SessionID) async throws -> TurnUsage? {
        nil
    }

    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {}
}

public struct NoOpTranscriptStore: TranscriptStore {
    public init() {}

    public func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        []
    }

    public func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}

    public func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
}

public actor FileTranscriptStore: TranscriptStore {
    public static var defaultDirectoryURL: URL {
        AppSupportLocator.appSupportDirectoryURL(
            home: FileManager.default.homeDirectoryForCurrentUser
        ).appending(path: "transcripts", directoryHint: .isDirectory)
    }

    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL = FileTranscriptStore.defaultDirectoryURL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        let url = fileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([ChatItem].self, from: data)
    }

    public func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        guard !items.isEmpty else { return }
        var stored = try await loadTranscript(for: sessionID)
        for item in items {
            if let index = stored.firstIndex(where: { $0.id == item.id }) {
                stored[index] = item
            } else {
                stored.append(item)
            }
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(stored)
        try data.write(to: fileURL(for: sessionID), options: [.atomic])
    }

    public func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(items)
        try data.write(to: fileURL(for: sessionID), options: [.atomic])
    }

    public func loadTurnUsageSnapshot(for sessionID: SessionID) async throws -> TurnUsage? {
        let url = usageFileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(TurnUsage.self, from: data)
    }

    public func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(usage)
        try data.write(to: usageFileURL(for: sessionID), options: [.atomic])
    }

    private func fileURL(for sessionID: SessionID) -> URL {
        directoryURL.appending(path: "\(sessionID.rawValue.uuidString).json")
    }

    private func usageFileURL(for sessionID: SessionID) -> URL {
        directoryURL.appending(path: "\(sessionID.rawValue.uuidString).usage.json")
    }
}
