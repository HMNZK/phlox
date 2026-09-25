import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// 07 C-43: 保存時の競合で、開いてから書き換えた別セッションの名前を出す。
@MainActor
struct FileTabLastWriterTests {
    @Test
    func namesTheOtherChatSessionThatEditedTheFileAfterItWasOpened() async throws {
        let (repo, file) = try makeRepository()
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

    private func makeRepository() throws -> (URL, URL) {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("filetab-writer-\(UUID().uuidString)")
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
