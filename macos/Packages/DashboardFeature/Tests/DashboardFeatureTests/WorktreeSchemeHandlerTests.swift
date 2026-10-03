import Foundation
import Testing
import WebKit
@testable import DashboardFeature

@Suite("作業フォルダ内の HTML リソース配信", .serialized)
struct WorktreeSchemeHandlerTests {
    @Test("日本語・空白・記号を一度の復号で元の相対パスへ戻す")
    func pathRoundTrip() throws {
        let path = "資料/画面 #1?.html"
        let url = try #require(WorktreeURL.url(for: path))
        #expect(WorktreeURL.relativePath(url) == path)
        #expect(WorktreeURL.relativePath(URL(string: "phlox-worktree://local/a.html?version=2#title")!) == "a.html")
    }

    @Test("裸のパーセント記号を含むファイル名も配信する", arguments: ["100%.html", "50%off.html", "100%done.htm", "%ZZ.html"])
    func literalPercentFileName(path: String) throws {
        let url = try #require(WorktreeURL.url(for: path))
        #expect(WorktreeURL.relativePath(url) == path)
    }

    @Test("不正なパス・符号化・ホストを拒否する", arguments: [
        "phlox-worktree://local/../secret", "phlox-worktree://local/%2e%2e/secret",
        "phlox-worktree://local/a%2f..%2fsecret", "phlox-worktree://local/%00.html",
        "phlox-worktree://local/%FF.html",
        "phlox-worktree://local/%252e%252e/secret", "phlox-worktree://local/%2500.html",
        "phlox-worktree://remote/a.html", "phlox-worktree://user@local/a.html",
        "phlox-worktree://local:80/a.html", "phlox-worktree://local//a.html",
        "file:///a.html"
    ])
    func invalidPaths(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(WorktreeURL.relativePath(url) == nil)
    }

    @Test("生成時にも相対パスの不正を拒否する", arguments: ["", "/a.html", "../a.html", "a/../b.html", "a\u{0}.html", "a//b.html"])
    func invalidInput(path: String) {
        #expect(WorktreeURL.url(for: path) == nil)
    }

    @Test("メイン文書は開始時の draft、サブリソースはディスクのバイトを返す")
    @MainActor func draftAndResources() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("ディスク".utf8).write(to: root.appendingPathComponent("index.html"))
        let image = Data(repeating: 0xAA, count: 1_000_001)
        try image.write(to: root.appendingPathComponent("image.png"))
        let handler = WorktreeSchemeHandler(root: root.path, documentPath: "index.html", draft: "未保存")
        let webView = WKWebView()
        let page = SchemeTask(url: WorktreeURL.url(for: "index.html")!)
        handler.webView(webView, start: page)
        handler.updateDraft("次の版")
        try await waitForCompletion(page)
        #expect(page.data == Data("未保存".utf8))
        #expect(page.response?.mimeType == "text/html")
        #expect(page.response?.textEncodingName == "utf-8")
        let resource = SchemeTask(url: WorktreeURL.url(for: "image.png")!)
        handler.webView(webView, start: resource)
        try await waitForCompletion(resource)
        #expect(resource.data == image)
        #expect(resource.response?.mimeType == "image/png")
        handler.stopAll()
    }

    @Test("外側への symlink・ディレクトリ・GET 以外を配信しない")
    @MainActor func containmentAndMethod() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        let worktree = root.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try Data("秘密".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: worktree.appendingPathComponent("external.html"), withDestinationURL: outside)
        let handler = WorktreeSchemeHandler(root: worktree.path, documentPath: "external.html", draft: "下書き")
        let webView = WKWebView()
        for path in ["external.html", "missing.html", "folder"] {
            let task = SchemeTask(url: WorktreeURL.url(for: path)!)
            handler.webView(webView, start: task)
            try await waitForCompletion(task)
            #expect(task.error != nil)
            #expect(task.response == nil)
        }
        let post = SchemeTask(url: WorktreeURL.url(for: "external.html")!, method: "POST")
        handler.webView(webView, start: post)
        try await waitForCompletion(post)
        #expect(post.error != nil)
        #expect(post.response == nil)
        handler.stopAll()
    }

    @Test("停止済みの読み込みには応答しない")
    @MainActor func stoppedTaskReceivesNothing() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("本文".utf8).write(to: root.appendingPathComponent("index.html"))
        let handler = WorktreeSchemeHandler(root: root.path, documentPath: "index.html", draft: "下書き")
        let task = SchemeTask(url: WorktreeURL.url(for: "index.html")!)
        let webView = WKWebView()
        handler.webView(webView, start: task)
        handler.webView(webView, stop: task)
        try await Task.sleep(for: .milliseconds(100))
        #expect(task.response == nil)
        #expect(task.data.isEmpty)
        #expect(!task.finished)
        #expect(task.error == nil)
        handler.stopAll()
    }

    @Test("応答開始後に停止されても残りのデータを返さない")
    @MainActor func stopsBetweenResponses() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("本文".utf8).write(to: root.appendingPathComponent("index.html"))
        let handler = WorktreeSchemeHandler(root: root.path, documentPath: "index.html", draft: "下書き")
        let task = SchemeTask(url: WorktreeURL.url(for: "index.html")!)
        let webView = WKWebView()
        task.onResponse = { handler.webView(webView, stop: task) }
        handler.webView(webView, start: task)
        let deadline = ContinuousClock.now + .seconds(2)
        while task.response == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(task.response != nil)
        #expect(task.data.isEmpty)
        #expect(!task.finished)
        #expect(task.error == nil)
        task.onResponse = nil
        handler.stopAll()
    }

    @Test("32 MB を超えるリソースは読み取り前に拒否する")
    func oversizedResourceIsNotRead() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.bin")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try file.close()
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        do {
            _ = try await service.resourceData("large.bin", read: { _ in
                Issue.record("上限超過のファイルを読み込もうとしました")
                return Data()
            })
            Issue.record("上限超過なのに配信に成功しました")
        } catch {
            #expect((error as? URLError)?.code == .dataLengthExceedsMaximum)
        }
    }

    @Test("32 MB ちょうどは許可し、超過はスキーム配信でも失敗する")
    @MainActor func resourceSizeBoundary() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large.bin")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(WorkingTreeService.maximumHTMLResourceSize))
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        let sentinel = Data("読み取りを呼んだ".utf8)
        #expect(try await service.resourceData("large.bin", read: { _ in sentinel }) == sentinel)
        try file.truncate(atOffset: UInt64(WorkingTreeService.maximumHTMLResourceSize + 1))
        let handler = WorktreeSchemeHandler(root: root.path, documentPath: "index.html", draft: "本文")
        let task = SchemeTask(url: WorktreeURL.url(for: "large.bin")!)
        handler.webView(WKWebView(), start: task)
        try await waitForCompletion(task)
        #expect((task.error as? URLError)?.code == .dataLengthExceedsMaximum)
        #expect(task.response == nil)
        #expect(task.data.isEmpty)
        #expect(!task.finished)
        handler.stopAll()
    }

    private func directory() throws -> URL {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = package.appendingPathComponent(".build/phlox-html-scheme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor private func waitForCompletion(_ task: SchemeTask) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !task.finished && task.error == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(task.finished || task.error != nil)
    }
}

@MainActor private final class SchemeTask: NSObject, @MainActor WKURLSchemeTask {
    let request: URLRequest
    var response: URLResponse?
    var data = Data()
    var finished = false
    var error: (any Error)?
    var onResponse: (() -> Void)?

    init(url: URL, method: String = "GET") {
        var request = URLRequest(url: url)
        request.httpMethod = method
        self.request = request
    }

    func didReceive(_ response: URLResponse) {
        self.response = response
        onResponse?()
    }
    func didReceive(_ data: Data) { self.data.append(data) }
    func didFinish() { finished = true }
    func didFailWithError(_ error: any Error) { self.error = error }
}
