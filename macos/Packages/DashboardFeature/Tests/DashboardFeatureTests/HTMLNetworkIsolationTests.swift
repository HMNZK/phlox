import AppKit
import CoreText
import Foundation
import Network
import Testing
import WebKit
@testable import DashboardFeature

@MainActor
struct HTMLNetworkIsolationTests {
    @Test
    func externalRequestsAreBlockedWhileWorktreeResourcesRender() async throws {
        let server = try HTMLLoopbackReceiver()
        let port = try await server.start()
        defer { server.stop() }
        let base = "http://127.0.0.1:\(port)"
        let (_, response) = try await URLSession.shared.data(from: URL(string: "\(base)/probe")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.requests.contains { $0.contains("/probe") })
        server.resetRequests()

        let html = """
        <html><head>
        <link rel="stylesheet" href="style.css">
        <link rel="stylesheet" href="\(base)/external.css">
        <style>
        @import url('\(base)/import.css');
        @font-face { font-family: RemoteFixture; src: url('\(base)/font.ttf'); }
        @font-face { font-family: LocalFixture; src: url('font.ttf'); }
        #remote-font { font-family: RemoteFixture; }
        #local-font { font-family: LocalFixture; }
        </style></head><body>
        <p id="content">スクリプトは未実行</p>
        <span id="remote-font">Remote</span><span id="local-font">Local</span>
        <img id="local-image" src="image.png"><img id="remote-image" src="\(base)/image.png">
        <iframe id="local-frame" src="frame.html"></iframe>
        <iframe src="\(base)/frame.html"></iframe>
        <script>document.getElementById('content').textContent = 'スクリプトが実行された';</script>
        </body></html>
        """
        let harness = try await HTMLRuntimeHarness(html: html, prepare: false)
        defer { harness.stop() }
        try Data("@import url('import.css'); #content { color: rgb(11, 22, 33); }".utf8)
            .write(to: harness.root.appendingPathComponent("style.css"))
        try Data("#content { background-color: rgb(44, 55, 66); }".utf8)
            .write(to: harness.root.appendingPathComponent("import.css"))
        try Data("<p>ローカルのフレーム</p>".utf8).write(to: harness.root.appendingPathComponent("frame.html"))
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { image.setColor(.red, atX: x, y: y) } }
        try #require(image.representation(using: .png, properties: [:]))
            .write(to: harness.root.appendingPathComponent("image.png"))
        let font = CTFontCreateWithName("ArialMT" as CFString, 12, nil)
        let fontURL = try #require(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
        try FileManager.default.copyItem(at: fontURL, to: harness.root.appendingPathComponent("font.ttf"))
        await harness.start()
        try await harness.waitForText("スクリプトは未実行")
        try await harness.waitForString("document.fonts.status", equals: "loaded")
        #expect(harness.model.ruleList != nil)
        #expect(!harness.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(!harness.webView.configuration.websiteDataStore.isPersistent)
        #expect(try await harness.string("document.getElementById('content').textContent") == "スクリプトは未実行")
        #expect(try await harness.string("getComputedStyle(document.getElementById('content')).color") == "rgb(11, 22, 33)")
        #expect(try await harness.string("getComputedStyle(document.getElementById('content')).backgroundColor") == "rgb(44, 55, 66)")
        #expect(try await harness.string("String(document.getElementById('local-image').naturalWidth)") == "2")
        #expect(try await harness.string("Array.from(document.fonts).find(f => f.family === 'LocalFixture').status") == "loaded")
        #expect(try await harness.string("document.getElementById('local-frame').contentDocument.body.textContent") == "ローカルのフレーム")
        #expect(try await harness.string("String(document.getElementById('remote-image').naturalWidth)") == "0")
        #expect(server.requests.isEmpty)
        #expect(server.connectionCount == 0)

        // 同じ文書を遮断なしで読むと要求が届くことも確認し、受信ゼロの偽陽性を防ぐ。
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(WorktreeSchemeHandler(root: harness.root.path, documentPath: "index.html", draft: html),
                                          forURLScheme: "phlox-worktree")
        let unblocked = WKWebView(frame: harness.webView.bounds, configuration: configuration)
        defer { unblocked.stopLoading() }
        harness.window.contentView = unblocked
        unblocked.load(URLRequest(url: URL(string: "phlox-worktree://local/index.html")!))
        try await HTMLRuntimeHarness.waitForText("スクリプトは未実行", in: unblocked)
        for path in ["external.css", "import.css", "font.ttf", "image.png", "frame.html"] {
            #expect(server.requests.contains { $0.contains("GET /\(path) ") }, "遮断なしで \(path) の要求が届きます")
        }
    }

    @Test("preconnect・ping・meta refresh・フォームは接続も要求も出さない",
          arguments: ["preconnect", "ping", "refresh", "form"])
    func activeNetworkVectorsAreBlocked(vector: String) async throws {
        let server = try HTMLLoopbackReceiver()
        let port = try await server.start()
        defer { server.stop() }
        let base = "http://127.0.0.1:\(port)"
        let (_, response) = try await URLSession.shared.data(from: URL(string: "\(base)/probe")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.connectionCount > 0)
        server.resetRequests()
        let markup: String
        switch vector {
        case "preconnect": markup = "<link rel='preconnect' href='\(base)'>"
        case "ping": markup = "<a id='link' href='#' ping='\(base)/ping'>リンク</a>"
        case "refresh": markup = "<meta http-equiv='refresh' content='0;url=\(base)/refresh'>"
        default: markup = "<form id='form' action='\(base)/form' method='post'><input name='value' value='本文'></form>"
        }
        let harness = try await HTMLRuntimeHarness(html: markup + "<p>本文</p>")
        defer { harness.stop() }
        try await harness.waitForText("本文")
        if vector == "ping" { _ = try await harness.string("document.querySelector('#link').click(); 'クリック済み'") }
        if vector == "form" { _ = try await harness.string("document.querySelector('#form').requestSubmit(); '送信要求済み'") }
        try await Task.sleep(for: .seconds(2))
        #expect(server.connectionCount == 0)
        #expect(server.requests.isEmpty)
        #expect(harness.webView.url?.fragment == nil || harness.webView.url?.fragment == "")
        #expect(WorktreeURL.relativePath(try #require(harness.webView.url)) == "index.html")
    }

    @Test("iframe の HTML と SVG のページスクリプトは実行しない")
    func childDocumentScriptsStayDisabled() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>本文</p><iframe id='html' src='frame.html'></iframe><iframe id='svg' src='image.svg'></iframe>", prepare: false)
        defer { harness.stop() }
        try Data("<p id='status'>未実行</p><script>document.querySelector('#status').textContent='実行済み';</script>".utf8)
            .write(to: harness.root.appendingPathComponent("frame.html"))
        try Data("<svg xmlns='http://www.w3.org/2000/svg'><text id='status'>未実行</text><script>document.getElementById('status').textContent='実行済み';</script></svg>".utf8)
            .write(to: harness.root.appendingPathComponent("image.svg"))
        await harness.start()
        try await harness.waitForText("本文")
        for frame in ["html", "svg"] {
            #expect(try await harness.string("document.querySelector('#\(frame)').contentDocument.getElementById('status').textContent") == "未実行")
        }
    }

    @Test
    func preparationFailureNeverLoadsAndKeepsSourcePresentation() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>読み込んではいけない本文</p>", prepare: false)
        defer { harness.stop() }
        harness.coordinator.update(harness.webView)
        #expect(harness.webView.url == nil)
        await harness.model.prepare(compile: { throw URLError(.cannotLoadFromNetwork) })
        harness.coordinator.update(harness.webView)
        #expect(harness.document.presentation == .source)
        #expect(harness.model.ruleList == nil)
        #expect(harness.model.preparationError != nil)
        #expect(harness.webView.url == nil)
        harness.model.reload()
        harness.coordinator.update(harness.webView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.webView.url == nil)
        #expect(!harness.webView.isLoading)
    }
}

/// 外へ接続せず、ループバックに届いた HTTP 要求だけを記録する。
private final class HTMLLoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HTMLNetworkIsolationTests.loopback")
    private let lock = NSLock()
    private var capturedRequests: [String] = []
    private var acceptedConnectionCount = 0
    private var connections: [NWConnection] = []
    private var startCompleted = false

    var connectionCount: Int { lock.withLock { acceptedConnectionCount } }

    var requests: [String] { lock.withLock { capturedRequests } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port?.rawValue else { return }
                    if self.claimStart() { continuation.resume(returning: port) }
                case .failed(let error):
                    if self.claimStart() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.withLock {
                    self.acceptedConnectionCount += 1
                    self.connections.append(connection)
                }
                connection.start(queue: self.queue)
                self.receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }

    private func claimStart() -> Bool {
        lock.withLock {
            guard !startCompleted else { return false }
            startCompleted = true
            return true
        }
    }

    func resetRequests() {
        let accepted = lock.withLock {
            capturedRequests.removeAll()
            acceptedConnectionCount = 0
            let accepted = connections
            connections.removeAll()
            return accepted
        }
        for connection in accepted { connection.cancel() }
    }

    func stop() {
        listener.cancel()
        let accepted = lock.withLock { connections }
        for connection in accepted { connection.cancel() }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { connection.cancel(); return }
            if let error {
                Issue.record("ローカル HTTP 受信に失敗しました: \(error)")
                connection.cancel()
                return
            }
            var bytes = accumulated
            if let data { bytes.append(data) }
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.lock.withLock { self.capturedRequests.append(String(decoding: bytes, as: UTF8.self)) }
                connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK".utf8),
                                completion: .contentProcessed { error in
                    if let error { Issue.record("ローカル HTTP 応答に失敗しました: \(error)") }
                    connection.cancel()
                })
            } else if done {
                connection.cancel()
            } else {
                self.receive(connection, accumulated: bytes)
            }
        }
    }
}
