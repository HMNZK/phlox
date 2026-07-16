// task-5 受け入れテスト（PM 著・実装役は編集禁止）
// 監査所見: JSONFileStore.save がパーミッション指定なしで書き込む（umask 依存で読み取り権限が
// 広がりうる）。sessions.json は機微情報を含んできたファイルであり、所有者のみ読書き（0600）にする。
import AgentDomain
import Foundation
import Testing
@testable import MessageStore

private func acceptanceSessionsFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("JSONFileStoreAcceptance-\(UUID().uuidString).json")
}

@Test func acceptance_jsonSessionStore_savesFileWithOwnerOnlyPermissions() async throws {
    let url = acceptanceSessionsFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = JSONSessionStore(fileURL: url)

    try await store.save([])

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.uint16Value & 0o777 == 0o600)
}

@Test func acceptance_jsonSessionStore_overwriteKeepsOwnerOnlyPermissions() async throws {
    // 既存ファイルがある状態の上書き（atomic write の置換後）でも 0600 が保たれること
    let url = acceptanceSessionsFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = JSONSessionStore(fileURL: url)

    try await store.save([])
    let descriptor = PersistedSessionDescriptor(
        id: SessionID(rawValue: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
        kind: .claudeCode,
        workingDirectory: "/tmp/work",
        name: "perm-check",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:]
    )
    try await store.save([descriptor])

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.uint16Value & 0o777 == 0o600)

    let loaded = await store.load()
    #expect(loaded.map(\.name) == ["perm-check"])
}
