import AppKit
import Foundation
import Testing
import WebKit
import AgentDomain
import LocalHTTPServer
import Network
@testable import DashboardFeature

@Suite("ブラウザタブ") @MainActor
struct BrowserTabTests {
    @Test func httpAccessIsLimitedToWebViews() throws {
        let macos = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // 生成済み Info.plist がなくても、通信設定の正本を検査する。
        let project = try String(contentsOf: macos.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(project.contains("NSAppTransportSecurity:\n          NSAllowsArbitraryLoadsInWebContent: true"))
        #expect(!project.contains("NSAllowsArbitraryLoads:"))
    }

    @Test(arguments: [
        ("example.com/slides?q=1#two", "https://example.com/slides?q=1#two"),
        (" http://localhost:8080/ ", "http://localhost:8080/"),
        ("localhost:3000", "https://localhost:3000"),
        ("/tmp/日本語 スライド.html", URL(fileURLWithPath: "/tmp/日本語 スライド.html").absoluteString),
        ("file:///tmp/a%20b.html", "file:///tmp/a%20b.html"),
        ("file:///tmp/slides.html#/2", "file:///tmp/slides.html#/2")
    ])
    func addresses(input: String, expected: String) {
        #expect(BrowserAddress.url(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", " \n ", "https://", "ftp://example.com", "mailto:a@example.com", "javascript:alert(1)", "file://remote/tmp/a", "two words", "https://user:password@example.com"])
    func invalidAddresses(_ input: String) { #expect(BrowserAddress.url(from: input) == nil) }

    @Test(arguments: [
        (ChildTab.browser, Optional<ChildTab>.none, ChildTab.conversation, Optional<ChildTab>.none),
        (ChildTab.browser, Optional(ChildTab.terminal), ChildTab.terminal, Optional<ChildTab>.none),
        (ChildTab.changes, Optional(ChildTab.browser), ChildTab.changes, Optional<ChildTab>.none),
        (ChildTab.browser, Optional(ChildTab.simulator), ChildTab.conversation, Optional<ChildTab>.none),
        (ChildTab.simulator, Optional(ChildTab.browser), ChildTab.conversation, Optional<ChildTab>.none),
        (ChildTab.changes, Optional(ChildTab.terminal), ChildTab.changes, Optional(ChildTab.terminal))
    ])
    func persistence(left: ChildTab, right: ChildTab?, savedLeft: ChildTab, savedRight: ChildTab?) throws {
        let suite = "phlox.browser.persistence.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = SessionID()
        var layout = SessionTabLayout()
        layout.tabs = [.conversation, .terminal, .changes, .browser, .simulator]
        layout.left = left
        layout.right = right
        layout.focusesRight = right != nil
        layout.splitFraction = 0.37
        let store = SessionTabStore(defaults: defaults)
        store.updateLayout(for: id) { $0 = layout }
        #expect(store.layout(for: id) == layout)
        let restored = SessionTabStore(defaults: defaults).layout(for: id)
        #expect(restored.tabs == [.conversation, .terminal, .changes])
        #expect(restored.left == savedLeft)
        #expect(restored.right == savedRight)
        #expect(restored.focusesRight == (savedRight != nil))
        #expect(restored.splitFraction == 0.37)
        let data = try #require(defaults.data(forKey: SessionTabStore.defaultsKey))
        #expect(!String(decoding: data, as: UTF8.self).contains("browser"))
    }

    @Test func localReadScope() throws {
        let root = try fixtureDirectory()
        defer { removeFixture(root) }
        let allowed = root.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.html")
        try Data().write(to: outside)
        let link = allowed.appendingPathComponent("escape.html")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(BrowserAddress.allowsNavigation(to: allowed.appendingPathComponent("assets/style.css"), readAccess: allowed))
        #expect(!BrowserAddress.allowsNavigation(to: outside, readAccess: allowed))
        #expect(!BrowserAddress.allowsNavigation(to: link, readAccess: allowed))
        #expect(!BrowserAddress.allowsNavigation(to: root.appendingPathComponent("allowed-other/a.html"), readAccess: allowed))
        #expect(!BrowserAddress.allowsNavigation(to: URL(string: "phlox://command")!, readAccess: allowed))
    }

    @Test func htmlButtonOpensSavedFileAndReusesTab() async throws {
        let root = try fixtureDirectory()
        defer { removeFixture(root) }
        let file = root.appendingPathComponent("slides.html")
        try Data("<h1>保存済み</h1>".utf8).write(to: file)
        let document = FileTabDocument(path: "slides.html", root: root.path)
        await document.loadIfNeeded()
        document.draft = "<h1>未保存</h1>"
        let session = SessionID()
        let router = AppRouter(selectedSession: session)
        let view = FileTabView(document: document, lastWriter: { _ in nil }, isFocused: true, openFile: { _, _ in })
        view.openInBrowser { router.openBrowser($0, for: session) }
        let model = try #require(router.browsers[session])
        #expect(model.url == file)
        #expect(router.tabs.layout(for: session).selected == .browser)
        view.openInBrowser { router.openBrowser($0, for: session) }
        #expect(router.browsers[session] === model)
        #expect(router.tabs.layout(for: session).tabs.filter { $0 == .browser }.count == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == "<h1>保存済み</h1>")
        model.submit(" ")
        #expect(model.url == file)
        router.closeBrowser(for: session)
        #expect(router.browsers[session] == nil)
    }

    @Test func localJavaScriptRunsWithoutPersistentData() async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let root = try fixtureDirectory()
        defer { removeFixture(root) }
        let file = root.appendingPathComponent("slides.html")
        try Data("<!doctype html><meta charset='utf-8'><h1 id='result'>変更前</h1><script>document.querySelector('#result').textContent='JavaScript 実行済み';document.title='スライド';</script>".utf8).write(to: file)
        let model = BrowserTabModel()
        model.open(file)
        let web = model.makeWebView()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        defer { model.close(); window.contentView = nil; window.close() }
        #expect(!web.configuration.websiteDataStore.isPersistent)
        #expect(web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        for selector in [
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:"
        ] {
            #expect(model.responds(to: NSSelectorFromString(selector)), "WebKit から呼び出せる: \(selector)")
        }
        let other = BrowserTabModel()
        let otherWeb = other.makeWebView()
        defer { other.close() }
        #expect(web.configuration.websiteDataStore !== otherWeb.configuration.websiteDataStore)
        let deadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != "スライド" {
            try #require(ContinuousClock.now < deadline, "ローカル HTML の読み込みが完了しない: \(model.error ?? "") / \(web.url?.absoluteString ?? "URLなし") / \(web.title ?? "タイトルなし") / 読み込み \(web.isLoading)")
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = try await web.evaluateJavaScript("document.querySelector('#result').textContent")
        #expect(result as? String == "JavaScript 実行済み")
        #expect(model.readAccess == root.resolvingSymlinksInPath())
        try Data("<!doctype html><meta charset='utf-8'><title>同じタブの次のページ</title><h1>移動先</h1>".utf8)
            .write(to: root.appendingPathComponent("next.html"))
        _ = try await web.evaluateJavaScript("window.open('next.html'); true")
        let nextDeadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != "同じタブの次のページ" {
            try #require(ContinuousClock.now < nextDeadline, "window.open が同じタブを開かない: \(model.error ?? "")")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.webView === web)

        #expect(web.canGoBack)
        model.back()
        let backDeadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != "スライド" {
            try #require(ContinuousClock.now < backDeadline, "戻る操作が完了しない")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(web.canGoForward)
        _ = try await web.evaluateJavaScript("document.body.innerHTML += '<a id=\"next\" href=\"next.html\" target=\"_blank\">次へ</a>'; document.querySelector('#next').click(); true")
        let linkDeadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != "同じタブの次のページ" {
            try #require(ContinuousClock.now < linkDeadline, "target=_blank が同じタブを開かない")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.webView === web)

        let folder = root.appendingPathComponent("別フォルダ", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let separate = folder.appendingPathComponent("index.html")
        try Data("<!doctype html><meta charset='utf-8'><title>別フォルダ</title>".utf8).write(to: separate)
        model.open(separate)
        try await waitForTitle("別フォルダ", in: web)
        #expect(model.readAccess == folder.resolvingSymlinksInPath(), "明示的に開いたファイルの親フォルダに切り替える")
        model.back()
        try await waitForTitle("同じタブの次のページ", in: web)
        #expect(model.readAccess == root.resolvingSymlinksInPath())
        model.forward()
        try await waitForTitle("別フォルダ", in: web)
        #expect(model.readAccess == root.resolvingSymlinksInPath(), "履歴の行き先が範囲内なら許可を保つ")

        let missing = root.appendingPathComponent("missing.html")
        model.open(missing)
        let failureDeadline = ContinuousClock.now + .seconds(10)
        while model.error == nil {
            try #require(ContinuousClock.now < failureDeadline, "読み込み失敗が表示されない")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.url == missing, "失敗した URL を再読込の行き先として保持する")
        try Data("<!doctype html><meta charset='utf-8'><title>再読込で復旧</title>".utf8).write(to: missing)
        model.reloadOrStop()
        let retryDeadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != "再読込で復旧" {
            try #require(ContinuousClock.now < retryDeadline, "失敗したページを再読込できない: \(model.url?.absoluteString ?? "")")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.error == nil)
    }

    @Test func bareAbsolutePathAndTilde() {
        let path = BrowserAddress.url(from: "/tmp/slides.html#/2")
        #expect(path?.path == "/tmp/slides.html")
        #expect(path?.fragment == "/2")
        let home = BrowserAddress.url(from: "~/Downloads/x.html")
        #expect(home?.isFileURL == true)
        #expect(home?.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/x.html").path)
    }

    @Test func pageOwnedFramesLoad() async throws {
        try await withPage("""
            <script>window.frameMessages=[]; addEventListener('message', event => frameMessages.push(event.data));</script>
            <iframe id='srcdoc' srcdoc='<body>srcdoc の本文</body>'></iframe>
            <iframe id='blank' src='about:blank' onload="this.contentDocument.body.textContent='blank の本文'"></iframe>
            <iframe id='data' src="data:text/html;charset=utf-8,<body><p>data の本文</p><script>parent.postMessage(document.querySelector('p').textContent,'*')</script>"></iframe>
            <iframe id='blob'></iframe><script>
            document.querySelector('#blob').src = URL.createObjectURL(new Blob(['<body>blob の本文</body>'], {type:'text/html'}));
            </script>
            """) { model, web, _ in
            try await Task.sleep(for: .milliseconds(500))
            let bodies = try await web.evaluateJavaScript("['srcdoc','blob'].map(id => document.getElementById(id).contentDocument?.body.textContent ?? '').join('|')")
            #expect(bodies as? String == "srcdoc の本文|blob の本文")
            #expect(try await web.evaluateJavaScript("document.getElementById('blank').contentDocument.body.textContent") as? String == "blank の本文")
            let messages = try await web.evaluateJavaScript("frameMessages") as? [String]
            #expect(messages?.contains("data の本文") == true)
            #expect(model.error == nil)
        }
    }

    @Test func subframeDownloadDoesNotCoverPage() async throws {
        let (listener, base) = try await httpServer(html: "<title>HTTP ページ</title><iframe src='/data.bin'></iframe>")
        defer { listener.cancel() }
        try await withPage("<p>移動前</p>") { model, web, _ in
            model.open(base)
            try await waitForTitle("HTTP ページ", in: web)
            try await Task.sleep(for: .milliseconds(500))
            #expect(model.error == nil)
            #expect(web.title == "HTTP ページ")
            #expect(listener.requestPaths.contains("/data.bin"), "子フレームの応答が実際に届いたことを確認する")
        }
    }

    @Test(arguments: [false, true]) func mainFrameDownloadKeepsMessage(downloadAttribute: Bool) async throws {
        let (listener, base) = try await httpServer(html: "<title>HTTP ページ</title><a id='download' href='/data.bin' \(downloadAttribute ? "download" : "")>取得</a>")
        defer { listener.cancel() }
        try await withPage("<p>移動前</p>") { model, web, _ in
            model.open(base)
            try await waitForTitle("HTTP ページ", in: web)
            _ = try await web.evaluateJavaScript("document.getElementById('download').click(); true")
            try await Task.sleep(for: .milliseconds(500))
            #expect(model.error == "ダウンロードには対応していません。")
            #expect(!model.isLoading)
        }
    }

    @Test func addressFollowsPushStateAfterFragment() async throws {
        try await withPage("<a id='fragment' href='#sec'>節</a><p id='sec'>本文</p>") { model, web, _ in
            _ = try await web.evaluateJavaScript("document.getElementById('fragment').click(); true")
            try await Task.sleep(for: .milliseconds(100))
            _ = try await web.evaluateJavaScript("history.pushState(null, '', '#pushed'); true")
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.url?.fragment == "pushed")
            _ = try await web.evaluateJavaScript("history.replaceState(null, '', '#replaced'); true")
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.url?.fragment == "replaced")
        }
    }

    @Test func unsupportedLinkLeavesPage() async throws {
        try await withPage("<a id='mail' href='mailto:a@example.com'>メール</a>") { model, web, file in
            _ = try await web.evaluateJavaScript("document.getElementById('mail').click(); true")
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.error == nil)
            #expect(model.url == file)
            #expect(web.url == file)
            #expect(try await web.evaluateJavaScript("document.getElementById('mail').textContent") as? String == "メール")
        }
    }

    @Test func httpNavigationClearsReadAccessAndRejectsFiles() async throws {
        let (listener, base) = try await httpServer(html: "<title>HTTP ページ</title><p>外部ページ</p>")
        defer { listener.cancel() }
        try await withPage("<a id='http' href='\(base.absoluteString)'>HTTP へ</a>") { model, web, file in
            _ = try await web.evaluateJavaScript("document.getElementById('http').click(); true")
            try await waitForTitle("HTTP ページ", in: web)
            #expect(model.readAccess == nil)
            let fileString = String(data: try JSONEncoder().encode(file.absoluteString), encoding: .utf8)!
            for script in [
                "const a=document.createElement('a'); a.href=\(fileString); document.body.append(a); a.click(); true",
                "window.open(\(fileString)); true",
                "const a=document.createElement('a'); a.href=\(fileString); a.target='_blank'; document.body.append(a); a.click(); true"
            ] {
                model.open(file)
                try await waitForTitle("回帰ページ", in: web)
                _ = try await web.evaluateJavaScript("document.getElementById('http').click(); true")
                try await waitForTitle("HTTP ページ", in: web)
                _ = try await web.evaluateJavaScript("(() => { \(script) })()")
                try await Task.sleep(for: .milliseconds(200))
                #expect(web.url == base)
                #expect(model.url == base)
                #expect(model.readAccess == nil)
                #expect(model.error == nil)
                #expect(try await web.evaluateJavaScript("document.body.textContent") as? String == "外部ページ")
            }
            model.submit(file.absoluteString)
            try await waitForTitle("回帰ページ", in: web)
            #expect(model.readAccess == file.deletingLastPathComponent().resolvingSymlinksInPath())
        }
    }

    @Test func subfolderLinkCanReturnToOpenedFolder() async throws {
        try await withPage("<a id='down' href='sub/page.html'>下へ</a>") { model, web, file in
            let root = file.deletingLastPathComponent()
            let sub = root.appendingPathComponent("sub", isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data("<!doctype html><meta charset='utf-8'><title>下のページ</title><a id='up' href='../index.html'>上へ</a>".utf8)
                .write(to: sub.appendingPathComponent("page.html"))
            _ = try await web.evaluateJavaScript("document.getElementById('down').click(); true")
            try await waitForTitle("下のページ", in: web)
            #expect(model.readAccess == root.resolvingSymlinksInPath())
            _ = try await web.evaluateJavaScript("document.getElementById('up').click(); true")
            try await waitForTitle("回帰ページ", in: web)
            model.back()
            try await waitForTitle("下のページ", in: web)
            #expect(model.readAccess == root.resolvingSymlinksInPath())
            model.forward()
            try await waitForTitle("回帰ページ", in: web)
            #expect(model.readAccess == root.resolvingSymlinksInPath())
        }
    }

    @Test(arguments: ["open", "blank"])
    func httpFrameCannotOpenLocalFile(mode: String) async throws {
        let (listener, base) = try await httpServer(html: """
            <script>setTimeout(() => { const t = decodeURIComponent(location.hash.slice(1));
            if ('\(mode)' === 'open') { window.open(t); } else { const a = document.createElement('a');
            a.href = t; a.target = '_blank'; document.body.append(a); a.click(); }
            parent.postMessage('試行済み', '*'); }, 100);</script>
            """)
        defer { listener.cancel() }
        try await withPage("<p>ローカル</p><script>window.addEventListener('message', e => { window.attempted = e.data; });</script>") { model, web, file in
            let root = file.deletingLastPathComponent()
            let other = root.appendingPathComponent("other.html")
            try Data("<!doctype html><meta charset='utf-8'><title>別のローカル</title>".utf8).write(to: other)
            let src = base.absoluteString + "#" + other.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            _ = try await web.evaluateJavaScript("const f=document.createElement('iframe'); f.src='\(src)'; document.body.append(f); true")
            try await Task.sleep(for: .milliseconds(800))
            #expect(listener.requestPaths.contains("/"), "外部の iframe が実際に読み込まれた")
            #expect(try await web.evaluateJavaScript("window.attempted") as? String == "試行済み", "iframe が移動を試みた")
            #expect(web.url == file)
            #expect(web.title == "回帰ページ")
            #expect(model.readAccess == root.resolvingSymlinksInPath())
            #expect(model.error == nil)
        }
    }

    @Test(arguments: [false, true])
    func failedHTTPNavigationKeepsLocalReadAccess(explicit: Bool) async throws {
        let (listener, base) = try await httpServer(html: "")
        defer { listener.cancel() }
        let destination = base.appendingPathComponent("fail")
        try await withPage("<a id='http' href='\(destination.absoluteString)'>HTTP へ</a>") { model, web, file in
            if explicit { model.open(destination) }
            else { _ = try await web.evaluateJavaScript("document.getElementById('http').click(); true") }
            let deadline = ContinuousClock.now + .seconds(10)
            while model.error == nil {
                try #require(ContinuousClock.now < deadline, "HTTP の失敗通知がない")
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(listener.requestPaths.contains("/fail"))
            #expect(web.url == file)
            #expect(web.title == "回帰ページ")
            #expect(model.readAccess == file.deletingLastPathComponent().resolvingSymlinksInPath())
        }
    }

    @Test(arguments: [false, true])
    func stoppedHTTPNavigationKeepsLocalReadAccess(explicit: Bool) async throws {
        let (listener, base) = try await httpServer(html: "")
        defer { listener.cancel() }
        let destination = base.appendingPathComponent("pending")
        try await withPage("<a id='http' href='\(destination.absoluteString)'>HTTP へ</a>") { model, web, file in
            if explicit { model.open(destination) }
            else { _ = try await web.evaluateJavaScript("document.getElementById('http').click(); true") }
            let deadline = ContinuousClock.now + .seconds(10)
            while !listener.requestPaths.contains("/pending") || !model.isLoading {
                try #require(ContinuousClock.now < deadline, "HTTP の移動開始が確認できない")
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(model.readAccess == file.deletingLastPathComponent().resolvingSymlinksInPath())
            model.reloadOrStop()
            try await Task.sleep(for: .milliseconds(200))
            #expect(web.url == file)
            #expect(web.title == "回帰ページ")
            #expect(model.readAccess == file.deletingLastPathComponent().resolvingSymlinksInPath())
            #expect(model.error == nil)
        }
    }

    private func withPage(_ html: String,
                          body: (BrowserTabModel, WKWebView, URL) async throws -> Void) async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let root = try fixtureDirectory()
        defer { removeFixture(root) }
        let file = root.appendingPathComponent("index.html")
        try Data("<!doctype html><meta charset='utf-8'><title>回帰ページ</title>\(html)".utf8).write(to: file)
        let model = BrowserTabModel()
        model.open(file)
        let web = model.makeWebView()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        defer { model.close(); window.contentView = nil; window.close() }
        try await waitForTitle("回帰ページ", in: web)
        try await body(model, web, file)
    }

    private func httpServer(html: String) async throws -> (BrowserHTTPServer, URL) {
        let server = try BrowserHTTPServer(html: html)
        do {
            let port = try await server.start()
            return (server, URL(string: "http://127.0.0.1:\(port)/")!)
        } catch {
            server.cancel()
            throw error
        }
    }

    private func waitForTitle(_ title: String, in web: WKWebView) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while web.isLoading || web.title != title {
            try #require(ContinuousClock.now < deadline, "ページの移動が完了しない: \(title) / 現在 \(web.title ?? "なし") / \(web.url?.absoluteString ?? "なし") / 読み込み \(web.isLoading)")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func fixtureDirectory() throws -> URL {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = package.appendingPathComponent(".build/browser-tests/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removeFixture(_ root: URL) {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("ブラウザのテスト用ファイルを削除できません: \(error)") }
    }
}

/// 画面外の WebKit 用。先行接続の正常な EOF と、要求・応答の失敗を分けて扱う。
private final class BrowserHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "phlox.browser.tests.http")
    private let html: String
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var stopped = false
    private var capturedPaths: [String] = []

    var requestPaths: [String] { lock.withLock { capturedPaths } }

    init(html: String) throws {
        self.html = html
        listener = try LocalHTTPListener.makeListener(port: 0)
    }

    func start() async throws -> Int {
        try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.withLock { self.connections.append(connection) }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
    }

    func cancel() {
        let active = lock.withLock {
            stopped = true
            let active = connections
            connections.removeAll()
            return active
        }
        listener.cancel()
        for connection in active { connection.cancel() }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self, !self.lock.withLock({ self.stopped }) else { connection.cancel(); return }
            if let error {
                Issue.record("回帰用 HTTP サーバーの受信に失敗: \(error)")
                connection.cancel()
                return
            }
            var bytes = accumulated
            if let data { bytes.append(data) }
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                do {
                    let request = try HTTPMessageParser.parse(bytes)
                    self.lock.withLock { self.capturedPaths.append(request.path) }
                    if request.path == "/pending" { return }
                    if request.path == "/fail" { connection.cancel(); return }
                    let download = request.path == "/data.bin"
                    let body = Data((download ? "ダウンロード" : self.html).utf8)
                    let response = HTTPResponseSerializer.serialize(statusCode: 200, statusText: "OK",
                        contentType: download ? "application/octet-stream" : "text/html; charset=utf-8", body: body)
                    connection.send(content: response, completion: .contentProcessed { error in
                        if let error, !self.lock.withLock({ self.stopped }) {
                            Issue.record("回帰用 HTTP サーバーの送信に失敗: \(error)")
                        }
                        connection.cancel()
                    })
                } catch {
                    Issue.record("回帰用 HTTP 要求の解析に失敗: \(error)")
                    connection.cancel()
                }
            } else if done {
                if !bytes.isEmpty { Issue.record("回帰用 HTTP 要求が未完了のまま切断されました") }
                connection.cancel()
            } else {
                self.receive(connection, accumulated: bytes)
            }
        }
    }
}
