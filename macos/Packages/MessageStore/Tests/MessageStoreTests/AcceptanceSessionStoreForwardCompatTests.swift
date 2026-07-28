import AgentDomain
import Foundation
import Testing
@testable import MessageStore

/// task-1 の受け入れテスト（不変・実装役は編集禁止）。
///
/// 契約: `sessions.json` の `launchContext` に**未知の文字列**が入っていても、
/// (a) そのセッションだけが安全側（`.interactive`）へ倒れ、
/// (b) **他のセッションを巻き添えにしない**。
///
/// なぜこれが要るか: `SessionLaunchContext` は素の `String` Codable enum で未知値に throw し、
/// `JSONFileStore.load()` はファイル全体を一括 decode するため、現状は
/// 「1件の未知値 → 全セッション消失＋ファイル隔離」になる。task-2 で enum に区分を足す前に、
/// この前方互換を成立させておく必要がある（旧バージョンへ戻したときの全損を防ぐ）。
struct AcceptanceSessionStoreForwardCompatTests {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ForwardCompat-sessions-\(UUID().uuidString).json")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".corrupt-"
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func descriptor(
        id: UUID,
        name: String,
        launchContext: SessionLaunchContext
    ) -> PersistedSessionDescriptor {
        PersistedSessionDescriptor(
            id: SessionID(rawValue: id),
            kind: .claudeCode,
            workingDirectory: "/tmp/forward-compat",
            name: name,
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            command: "claude",
            args: [],
            env: [:],
            launchContext: launchContext
        )
    }

    /// 未知の `launchContext` 値を持つ1件があっても、他の全セッションが復元される。
    /// 未知値の1件自体も失われず `.interactive`（安全側）として復元される。
    @Test func unknownLaunchContext_doesNotDestroyOtherSessions() async throws {
        let url = temporaryURL()
        defer { cleanup(url) }

        let alphaID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let bravoID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let charlieID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!

        let store = JSONSessionStore(fileURL: url)
        try await store.save([
            descriptor(id: alphaID, name: "Alpha", launchContext: .interactive),
            descriptor(id: bravoID, name: "Bravo", launchContext: .orchestration),
            descriptor(id: charlieID, name: "Charlie", launchContext: .orchestration),
        ])

        // 将来バージョンが書いた未知の区分を模倣する（Bravo の1件だけを書き換える）。
        var text = try String(contentsOf: url, encoding: .utf8)
        let unknownMarker = "\"launchContext\":\"orchestration\""
        let replacement = "\"launchContext\":\"someFutureContext\""
        let firstRange = try #require(text.range(of: unknownMarker))
        text.replaceSubrange(firstRange, with: replacement)
        try Data(text.utf8).write(to: url, options: .atomic)

        let reloaded = JSONSessionStore(fileURL: url)
        let loaded = await reloaded.load()

        // 巻き添えゼロ: 3件すべて復元される。
        #expect(loaded.count == 3)
        let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id.rawValue, $0) })
        #expect(byID[alphaID]?.launchContext == .interactive)
        #expect(byID[charlieID]?.launchContext == .orchestration)
        // 未知値は安全側（ユーザーのセッションとして見える側）へ倒す。
        #expect(byID[bravoID]?.launchContext == .interactive)
    }

    /// 未知値があってもファイルは破損扱いされない（隔離されない・消えない）。
    @Test func unknownLaunchContext_doesNotQuarantineFile() async throws {
        let url = temporaryURL()
        defer { cleanup(url) }

        let store = JSONSessionStore(fileURL: url)
        try await store.save([
            descriptor(
                id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
                name: "Solo",
                launchContext: .orchestration
            )
        ])

        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(
            of: "\"launchContext\":\"orchestration\"",
            with: "\"launchContext\":\"someFutureContext\""
        )
        try Data(text.utf8).write(to: url, options: .atomic)

        let reloaded = JSONSessionStore(fileURL: url)
        let loaded = await reloaded.load()

        #expect(loaded.count == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".corrupt-"
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.filter { $0.lastPathComponent.hasPrefix(prefix) }.isEmpty)
    }

    /// 既存挙動の非退行: キー欠落は従来どおり `.interactive`、既知値は往復で不変。
    @Test func knownAndMissingLaunchContext_areUnchanged() async throws {
        let url = temporaryURL()
        defer { cleanup(url) }

        let interactiveID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!
        let orchestrationID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000002")!

        let store = JSONSessionStore(fileURL: url)
        try await store.save([
            descriptor(id: interactiveID, name: "Interactive", launchContext: .interactive),
            descriptor(id: orchestrationID, name: "Orchestration", launchContext: .orchestration),
        ])

        // `.interactive` はキー自体が書かれない（既存の encode 契約）。
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.components(separatedBy: "\"launchContext\"").count - 1 == 1)

        let loaded = await JSONSessionStore(fileURL: url).load()
        let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id.rawValue, $0) })
        #expect(byID[interactiveID]?.launchContext == .interactive)
        #expect(byID[orchestrationID]?.launchContext == .orchestration)
    }
}
