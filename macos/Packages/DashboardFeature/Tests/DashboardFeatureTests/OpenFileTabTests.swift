import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("要求時のルートでファイルタブを開く")
@MainActor
struct OpenFileTabTests {
    @Test("作業場所の変更中は旧ルートを開かず、完了後に新しい要求を受ける")
    func rejectsRequestsDuringWorkspaceChange() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        let registry = FileTabDocumentRegistry.shared
        #expect(registry.beginWorkspaceChange(id))
        defer { registry.endWorkspaceChange(id) }
        #expect(!files.openFileTab(
            sessionID: id, root: "/A", relativePath: "a.txt", router: router,
            requestedWorkingDirectory: "/A", currentWorkingDirectory: "/A"
        ))
        #expect(files.existing(for: id, path: "a.txt") == nil)
        registry.endWorkspaceChange(id)
        #expect(files.openFileTab(
            sessionID: id, root: "/B", relativePath: "a.txt", router: router,
            requestedWorkingDirectory: "/B", currentWorkingDirectory: "/B"
        ))
        #expect(files.existing(for: id, path: "a.txt")?.root == "/B")
    }

    @Test("作業場所が変わった要求は文書とタブを作らない")
    func discardsRequestAfterWorkspaceChanges() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        #expect(!files.openFileTab(
            sessionID: id, root: "/A", relativePath: "same.txt", router: router,
            requestedWorkingDirectory: "/A/sub", currentWorkingDirectory: "/B/sub"
        ))
        #expect(files.existing(for: id, path: "same.txt") == nil)
        #expect(router.tabs.layout(for: id).tabs == [.conversation])
    }

    @Test("要求したルートを保持し単体表示へ切り替えて共通ターミナルを解除する")
    func opensUsingCapturedRoot() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        router.viewMode = .grid
        router.commonTerminalSelected = true
        #expect(files.openFileTab(
            sessionID: id, root: "/A", relativePath: "sub/a.txt", router: router,
            requestedWorkingDirectory: "/A/sub", currentWorkingDirectory: "/A/sub"
        ))
        #expect(files.existing(for: id, path: "sub/a.txt")?.root == "/A")
        #expect(router.viewMode == .single)
        #expect(!router.commonTerminalSelected)
        #expect(router.tabs.layout(for: id).selected == .file("sub/a.txt"))
    }

    @Test("既存文書を維持して前に出し、分割指定なら右の区画へ開く")
    func reusesDocumentAndSplitsRight() {
        let files = FileTabDocuments()
        let router = AppRouter()
        let id = SessionID()
        func open(split: Bool = false) -> Bool {
            files.openFileTab(
                sessionID: id, root: "/A", relativePath: "a.txt", split: split, router: router,
                requestedWorkingDirectory: "/A", currentWorkingDirectory: "/A"
            )
        }
        #expect(open())
        let document = files.existing(for: id, path: "a.txt")
        router.tabs.updateLayout(for: id) { $0.select(.conversation) }
        #expect(open())
        #expect(files.existing(for: id, path: "a.txt") === document)
        #expect(router.tabs.layout(for: id).tabs == [.conversation, .file("a.txt")])
        router.tabs.updateLayout(for: id) { $0.select(.conversation) }
        #expect(open(split: true))
        #expect(router.tabs.layout(for: id).left == .conversation)
        #expect(router.tabs.layout(for: id).right == .file("a.txt"))
    }

    @Test("リンクの相対パスはリンク名を保つ")
    func relativePathKeepsRequestedPath() {
        #expect(FileTabOpening.relativePath(of: URL(fileURLWithPath: "/A/link.txt"), under: "/A") == "link.txt")
        #expect(FileTabOpening.relativePath(of: URL(fileURLWithPath: "/AB/a.txt"), under: "/A") == nil)
    }
}
