import AgentDomain
import Foundation
import Testing
@testable import MessageStore

struct SessionStoreDecodeWhiteboxTests {
    @Test func discardedElement_originalRemainsRecoverableAfterSave() async throws {
        let url = temporaryURL()
        defer { cleanup(url) }
        let firstID = SessionID(rawValue: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!)
        let brokenID = SessionID(rawValue: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000002")!)
        let thirdID = SessionID(rawValue: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000003")!)
        try await JSONSessionStore(fileURL: url).save([
            descriptor(id: firstID, name: "First"),
            descriptor(id: brokenID, name: "Broken"),
            descriptor(id: thirdID, name: "Third"),
        ])

        let malformedData = try makeSecondSessionMalformed(at: url)
        try malformedData.write(to: url, options: .atomic)

        let store = JSONSessionStore(fileURL: url)
        let loaded = await store.load()

        #expect(loaded.map(\.id) == [firstID, thirdID])
        #expect(FileManager.default.fileExists(atPath: url.path))
        let backup = try #require(backupURLs(for: url).only)
        #expect(try Data(contentsOf: backup) == malformedData)

        try await store.save(loaded)

        #expect(try Data(contentsOf: backup) == malformedData)
        #expect(try Data(contentsOf: url) != malformedData)
    }

    @Test func repeatedLoadsOfSameDiscardedContent_createOnlyOneBackup() async throws {
        let url = temporaryURL()
        defer { cleanup(url) }
        try await JSONSessionStore(fileURL: url).save([
            descriptor(
                id: SessionID(
                    rawValue: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!
                ),
                name: "First"
            ),
            descriptor(
                id: SessionID(
                    rawValue: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000002")!
                ),
                name: "Broken"
            ),
        ])

        let malformedData = try makeSecondSessionMalformed(at: url)
        try malformedData.write(to: url, options: .atomic)
        let store = JSONSessionStore(fileURL: url)

        _ = await store.load()
        _ = await store.load()
        _ = await store.load()

        let backups = try backupURLs(for: url)
        #expect(backups.count == 1)
        let backup = try #require(backups.only)
        #expect(try Data(contentsOf: backup) == malformedData)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreDecode-\(UUID().uuidString).json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        for backup in (try? backupURLs(for: url)) ?? [] {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private func backupURLs(for url: URL) throws -> [URL] {
        let prefix = url.lastPathComponent + ".corrupt-"
        return try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private func makeSecondSessionMalformed(at url: URL) throws -> Data {
        let savedData = try Data(contentsOf: url)
        var envelope = try #require(
            JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        )
        var sessions = try #require(envelope["sessions"] as? [[String: Any]])
        sessions[1]["name"] = 42
        envelope["sessions"] = sessions
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func descriptor(id: SessionID, name: String) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: id,
            kind: .claudeCode,
            workingDirectory: "/tmp/session-store-decode",
            name: name,
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            command: "claude",
            args: [],
            env: [:]
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
