import AgentDomain
import Foundation
import os

private struct SessionsFile: Codable, Sendable {
    var schemaVersion: Int = 1
    var sessions: [PersistedSessionDescriptor]
    var discardedSessionCount: Int = 0

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sessions
    }

    init(schemaVersion: Int = 1, sessions: [PersistedSessionDescriptor]) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 版番号の無いファイルは 1 とみなす（版番号しか違わないファイルを壊れた扱いで退避しない）。
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let decodedSessions = try container.decode(
            [DiscardableSession].self,
            forKey: .sessions
        )
        sessions = decodedSessions.compactMap(\.value)
        discardedSessionCount = decodedSessions.count - sessions.count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessions, forKey: .sessions)
    }
}

private struct DiscardableSession: Decodable {
    private static let logger = Logger(
        subsystem: "com.phlox.Phlox",
        category: "JSONSessionStore"
    )

    let value: PersistedSessionDescriptor?

    init(from decoder: Decoder) throws {
        do {
            value = try PersistedSessionDescriptor(from: decoder)
        } catch {
            let identifier: String
            if
                let container = try? decoder.container(keyedBy: CodingKeys.self),
                let sessionID = try? container.decode(SessionID.self, forKey: .id)
            {
                identifier = sessionID.description
            } else {
                identifier = "unavailable"
            }
            Self.logger.warning(
                "discarding undecodable session id=\(identifier, privacy: .public) at \(String(describing: decoder.codingPath), privacy: .public): \(String(describing: error), privacy: .public)"
            )
            value = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

public actor JSONSessionStore: SessionStoreProtocol {
    private let fileURL: URL
    private let store: JSONFileStore<SessionsFile>
    private let logger = Logger(
        subsystem: "com.phlox.Phlox",
        category: "JSONSessionStore"
    )
    private var discardedSessionCountToNotify = 0
    private var requiresDiscardedSessionsBackup = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        store = JSONFileStore(fileURL: fileURL, category: "JSONSessionStore")
    }

    /// `load()` と同じ復号で読めるか。移行の前に確かめる（C-64）。
    public static func canRead(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(SessionsFile.self, from: data)) != nil
    }

    public func load() async -> [PersistedSessionDescriptor] {
        guard let file = store.load() else {
            return []
        }
        if file.discardedSessionCount > 0 {
            discardedSessionCountToNotify = max(discardedSessionCountToNotify, file.discardedSessionCount)
            requiresDiscardedSessionsBackup = true
            do {
                try backupSourceContainingDiscardedSessions()
                requiresDiscardedSessionsBackup = false
                try store.save(SessionsFile(schemaVersion: file.schemaVersion, sessions: file.sessions))
            } catch {
                logger.error(
                    "failed to persist sessions without discarded elements \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        return file.sessions
    }

    public func takeDiscardedSessionCount() async -> Int {
        defer { discardedSessionCountToNotify = 0 }
        return discardedSessionCountToNotify
    }

    public func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        if requiresDiscardedSessionsBackup {
            do {
                try backupSourceContainingDiscardedSessions()
                requiresDiscardedSessionsBackup = false
            } catch {
                try saveKeepingDiscardedSessions(sessions)
                return
            }
        }
        try store.save(SessionsFile(schemaVersion: 1, sessions: sessions))
    }

    private func saveKeepingDiscardedSessions(_ sessions: [PersistedSessionDescriptor]) throws {
        let source = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
        guard let envelope = source as? [String: Any], let elements = envelope["sessions"] as? [Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let discarded = try elements.filter { element in
            let data = try JSONSerialization.data(withJSONObject: element, options: .fragmentsAllowed)
            return (try? JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)) == nil
        }
        let encoded = try JSONEncoder().encode(sessions)
        let current = try JSONSerialization.jsonObject(with: encoded) as? [Any]
        guard let current else { throw CocoaError(.fileWriteUnknown) }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sessions": current + discarded], options: .sortedKeys)
        try store.save(data: data)
    }

    private func backupSourceContainingDiscardedSessions() throws {
        do {
            let sourceData = try Data(contentsOf: fileURL)
            let fileManager = FileManager.default
            let directory = fileURL.deletingLastPathComponent()
            let backupPrefix = fileURL.lastPathComponent + ".corrupt-"
            let existingBackups = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) }

            for backupURL in existingBackups {
                if
                    let backupData = try? Data(contentsOf: backupURL),
                    backupData == sourceData
                {
                    return
                }
            }

            var timestamp = Int(Date().timeIntervalSince1970)
            var destination = fileURL.appendingPathExtension(
                "corrupt-\(timestamp)"
            )
            while fileManager.fileExists(atPath: destination.path) {
                timestamp += 1
                destination = fileURL.appendingPathExtension(
                    "corrupt-\(timestamp)"
                )
            }
            try fileManager.copyItem(at: fileURL, to: destination)
            logger.warning(
                "backed up sessions source containing discarded elements to \(destination.path, privacy: .public)"
            )
        } catch {
            logger.error(
                "failed to back up sessions source containing discarded elements \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }
}
