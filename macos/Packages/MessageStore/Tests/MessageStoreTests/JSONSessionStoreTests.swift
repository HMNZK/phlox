import AgentDomain
import Foundation
import Testing
@testable import MessageStore

private struct SessionsFileEnvelope: Decodable {
    let schemaVersion: Int
    let sessions: [PersistedSessionDescriptor]
}

private func temporarySessionsFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("MessageStoreTests-sessions-\(UUID().uuidString).json")
}

private func removeSessionsFile(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove test sessions file \(url.path): \(error)")
    }
}

private func inodeNumber(at path: String) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    let number = try #require(attributes[.systemFileNumber] as? NSNumber)
    return number.uint64Value
}

private func quarantinedSessionFiles(for url: URL) -> [URL] {
    let directory = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + ".corrupt-"
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )) ?? []
    return contents.filter { $0.lastPathComponent.hasPrefix(prefix) }
}

private func removeQuarantinedSessionFiles(for url: URL) {
    for fileURL in quarantinedSessionFiles(for: url) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private func makeDescriptor(
    id: SessionID = SessionID(rawValue: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!),
    kind: AgentKind = .claudeCode,
    workingDirectory: String = "/tmp/test-session",
    name: String = "Test Session",
    projectID: ProjectID? = ProjectID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
    startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
    command: String = "claude",
    args: [String] = ["--print", "hello"],
    env: [String: String] = ["FOO": "bar", "BAZ": "qux"]
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: id,
        kind: kind,
        workingDirectory: workingDirectory,
        name: name,
        projectID: projectID,
        startedAt: startedAt,
        command: command,
        args: args,
        env: env
    )
}

struct JSONSessionStoreTests {
    @Test func saveAndLoad_roundTrip() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let store = JSONSessionStore(fileURL: url)
        let sessions = [
            makeDescriptor(workingDirectory: "/tmp/alpha", name: "Alpha"),
            makeDescriptor(
                kind: .cursor,
                workingDirectory: "/tmp/beta",
                name: "Beta",
                projectID: nil
            ),
        ]

        try await store.save(sessions)
        let loaded = await store.load()

        #expect(loaded == sessions)
    }

    @Test func load_missingFileReturnsEmpty() async {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let store = JSONSessionStore(fileURL: url)
        let loaded = await store.load()

        #expect(loaded.isEmpty)
    }

    @Test func load_invalidJSONReturnsEmpty() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }
        defer { removeQuarantinedSessionFiles(for: url) }

        try "{ not valid json }".data(using: .utf8)!.write(to: url, options: .atomic)

        let store = JSONSessionStore(fileURL: url)
        let loaded = await store.load()

        #expect(loaded.isEmpty)
    }

    @Test func load_corruptFileIsQuarantinedBeforeReturningEmpty() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }
        defer { removeQuarantinedSessionFiles(for: url) }

        let corruptData = try #require("{ not valid json }".data(using: .utf8))
        try corruptData.write(to: url, options: .atomic)

        let store = JSONSessionStore(fileURL: url)
        let loaded = await store.load()

        // 破損ファイルは退避され、次の save が破損データを上書きできないようにする
        #expect(loaded.isEmpty)
        let quarantined = quarantinedSessionFiles(for: url)
        #expect(quarantined.count == 1)
        let preserved = try Data(contentsOf: try #require(quarantined.first))
        #expect(preserved == corruptData)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func save_writesSchemaVersionWrapper() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let store = JSONSessionStore(fileURL: url)
        let sessions = [makeDescriptor()]

        try await store.save(sessions)

        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(SessionsFileEnvelope.self, from: data)

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.sessions == sessions)
    }

    @Test func save_preservesAllFields() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let sessionID = SessionID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let projectID = ProjectID(rawValue: UUID(uuidString: "FFFFFFFF-1111-2222-3333-444444444444")!)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let descriptor = makeDescriptor(
            id: sessionID,
            kind: .codex,
            workingDirectory: "/Users/dev/project",
            name: "Codex Session",
            projectID: projectID,
            startedAt: startedAt,
            command: "/usr/local/bin/codex",
            args: ["--model", "gpt-5", "--cwd", "/Users/dev/project"],
            env: ["PATH": "/usr/bin", "HOME": "/Users/dev"]
        )

        let store = JSONSessionStore(fileURL: url)
        try await store.save([descriptor])
        let loaded = await store.load()

        #expect(loaded.count == 1)
        let restored = try #require(loaded.first)
        #expect(restored.id == sessionID)
        #expect(restored.kind == .codex)
        #expect(restored.workingDirectory == "/Users/dev/project")
        #expect(restored.name == "Codex Session")
        #expect(restored.projectID == projectID)
        #expect(restored.startedAt == startedAt)
        #expect(restored.command == "/usr/local/bin/codex")
        #expect(restored.args == ["--model", "gpt-5", "--cwd", "/Users/dev/project"])
        #expect(restored.env == ["PATH": "/usr/bin", "HOME": "/Users/dev"])
    }

    // 同一内容の連続 save はディスク書き込み（atomic rename）を行わないため実ファイルの inode が
    // 変わらないこと、内容が変わったら必ず書き込まれ inode が変わることを確認する。
    // mtime 比較は解像度の粗さで flaky になりうるため inode 比較を用いる。
    @Test func save_unchangedContentSkipsDiskWriteButChangedContentAlwaysWrites() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let store = JSONSessionStore(fileURL: url)
        let sessions = [makeDescriptor()]

        try await store.save(sessions)
        let inodeAfterFirstSave = try inodeNumber(at: url.path)

        try await store.save(sessions)
        let inodeAfterUnchangedSave = try inodeNumber(at: url.path)
        #expect(inodeAfterUnchangedSave == inodeAfterFirstSave)

        try await store.save([makeDescriptor(name: "Changed")])
        let inodeAfterChangedSave = try inodeNumber(at: url.path)
        #expect(inodeAfterChangedSave != inodeAfterFirstSave)
    }

    // 差し戻し#1（ステージ1レビュー MEDIUM）: 無変更スキップの判定がプロセス内キャッシュのみだと、
    // 外部プロセスによるファイル書き換え（ドリフト）後に同一内容を save しても誤ってスキップし、
    // 元データが失われたまま気づけない。ディスク実体の stat 照合を追加したことで、ドリフト後の
    // save は必ず書き込みが行われ、元データへ復旧できることを確認する。
    @Test func save_afterExternalDriftRewritesEvenWithUnchangedContent() async throws {
        let url = temporarySessionsFileURL()
        defer { removeSessionsFile(at: url) }

        let store = JSONSessionStore(fileURL: url)
        let sessions = [makeDescriptor()]
        try await store.save(sessions)

        // 外部プロセスによる書き換えを模倣する（store インスタンスのプロセス内キャッシュは
        // 更新されないまま、ディスク実体だけが変わる）。
        try Data("{}".utf8).write(to: url, options: .atomic)

        // アプリ視点では内容は変わっていない（同じ sessions）が、ディスク実体は外部で
        // 上書きされている。stat 照合がなければキャッシュ一致のみでスキップしてしまう。
        try await store.save(sessions)

        // 別インスタンスの load で元データが読めること（外部ドリフト後も save が正しく復旧する）。
        let reloadedStore = JSONSessionStore(fileURL: url)
        let loaded = await reloadedStore.load()
        #expect(loaded == sessions)
    }
}
