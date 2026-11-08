import Foundation
import Testing
import AgentDomain
import HookServer
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// 07 C-43: 保存時の競合で、開いてから書き換えた別セッションの名前を出す。
@MainActor
struct FileTabLastWriterTests {
    @Test
    func namesTheOtherChatSessionThatEditedTheFileAfterItWasOpened() async throws {
        let (repo, file) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        // タブのパスは Git のルート基準、開いたセッションの作業場所はその下位フォルダ。
        let document = FileTabDocument(path: "sub/a.txt", workingDirectory: repo.appendingPathComponent("sub").path)
        let (other, client) = try await makeChat(named: "アザミ", workingDirectory: repo.path)
        let ownID = SessionID()
        #expect(document.lastWriter(among: [.appServer(other)], excluding: ownID) == nil, "開く前は何も分からない")
        await document.loadIfNeeded()
        #expect(document.lastWriter(among: [.appServer(other)], excluding: ownID) == nil, "まだ誰も書き換えていない")

        client.yield(.fileChange(itemId: "edit-other", [FilePatchChange(path: "sub/b.txt", diff: "")]))
        client.yield(.fileChange(itemId: "edit", [FilePatchChange(path: "sub/a.txt", diff: "")]))
        try await waitUntil { other.transcript.contains { $0.id == "edit" } }
        try "by chat".write(to: file, atomically: true, encoding: .utf8)

        #expect(try await document.save() == .conflictDetected)
        #expect(document.lastWriter(among: [.appServer(other)], excluding: ownID) == "アザミ · Codex")
        #expect(document.lastWriter(among: [.appServer(other)], excluding: other.id) == nil, "自分の変更は相手にしない")
    }

    @Test
    func fallsBackWhenSomethingElseRewroteTheFileAfterTheChat() async throws {
        let (repo, file) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let document = FileTabDocument(path: "sub/a.txt", workingDirectory: repo.path)
        let (other, client) = try await makeChat(named: "アザミ", workingDirectory: repo.path)
        await document.loadIfNeeded()

        client.yield(.fileChange(itemId: "edit", [FilePatchChange(path: file.path, diff: "")]))
        try await waitUntil { other.transcript.contains { $0.id == "edit" } }
        // チャットの後でターミナルが書き換えた（更新時刻が変更の記録より十分あと）。
        try "by terminal".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(FileTabDocument.writeTolerance + 60)], ofItemAtPath: file.path
        )

        #expect(document.lastWriter(among: [.appServer(other)], excluding: SessionID()) == nil)
    }

    @Test
    func runtimeConflictLookupNamesWriterWithoutLoadingOtherChatHistory() async throws {
        let (repo, file) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let document = FileTabDocument(path: "sub/a.txt", workingDirectory: repo.path)
        let client = EventYieldingStructuredClient()
        let (hooks, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hooks,
            workspaceDirectory: repo, agentBinaryPaths: [.claudeCode: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, _ in client })
        let owned = DashboardViewModel(environment: environment, paneLayoutStore: nil)
        await owned.start()
        let writerID = try await owned.spawnNewSession(ref: .builtin(.claudeCode), backend: .appServer,
            workingDirectoryOverride: repo.path, isolationOverride: false)
        let writer = try #require(owned.sessionNode(id: writerID)?.appServer)
        writer.name = "アザミ"
        await document.loadIfNeeded()
        client.yield(.fileChange(itemId: "edit", [FilePatchChange(path: "sub/a.txt", diff: "")]))
        try await waitUntil { writer.transcript.contains { $0.id == "edit" } }
        try "by chat".write(to: file, atomically: true, encoding: .utf8)
        let saveResult = try await document.save()
        #expect(document.lastWriter(among: owned.sessionNodes, excluding: SessionID()) == "アザミ · Claude Code")
        let screen = try DashboardViewModel(overview: owned.makeRuntimeOverview()) {
            try await owned.performRuntimeCommand($0)
        }
        screen.runtimeContentLoader = { _ in throw DashboardRuntimeError.invalidRequest }

        let name = try await screen.lastWriterForConflict(document, excluding: SessionID())

        #expect(saveResult == .conflictDetected)
        #expect(name == "アザミ · Claude Code")
        #expect(screen.sessionNode(id: writerID)?.appServer?.transcript.isEmpty == true)
    }

    @Test
    func runtimeConflictLookupRejectsRelativeFilePath() async throws {
        let (hooks, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hooks)
        let owned = DashboardViewModel(environment: environment, paneLayoutStore: nil)

        await #expect(throws: DashboardRuntimeError.invalidRequest) {
            try await owned.performRuntimeCommand(.fileLastWriter(
                absolutePath: "sub/a.txt", baselineAt: Date(timeIntervalSince1970: 1_700_000_000), excluding: nil))
        }
    }

    private func makeRepository() throws -> (URL, URL) {
        let scratch = ProcessInfo.processInfo.environment["SWIFT_TEST_SCRATCH_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let repo = scratch.appendingPathComponent("filetab-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let file = repo.appendingPathComponent("sub/a.txt")
        try "a".write(to: file, atomically: true, encoding: .utf8)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q"]
        git.currentDirectoryURL = repo
        try git.run()
        git.waitUntilExit()
        return (repo, file)
    }

    private func makeChat(named name: String, workingDirectory: String) async throws -> (ChatSessionViewModel, EventYieldingStructuredClient) {
        let client = EventYieldingStructuredClient()
        let chat = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: workingDirectory,
            transcriptStore: RecordingTranscriptStore()
        )
        chat.name = name
        try await chat.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        return (chat, client)
    }
}
