import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import DashboardFeature

@MainActor
struct HTMLPreviewRefreshTests {
    @Test
    func sourceReturnRendersUnsavedDraft() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>ディスクの本文</p>")
        defer { harness.stop() }
        try await harness.waitForText("ディスクの本文")
        harness.document.presentation = .source
        harness.coordinator.stop()
        harness.document.draft = "<p>未保存の本文</p>"
        harness.document.presentation = .rendered
        let coordinator = HTMLPreviewView.Coordinator(model: harness.model, openFile: { _ in })
        let webView = coordinator.makeWebView()
        defer { coordinator.stop() }
        harness.window.contentView = webView
        coordinator.update(webView)
        try await HTMLRuntimeHarness.waitForText("未保存の本文", in: webView)
        #expect(harness.document.isDirty)
        #expect(try String(contentsOf: harness.root.appendingPathComponent("index.html"), encoding: .utf8) == "<p>ディスクの本文</p>")
    }

    @Test
    func reloadRendersLatestDraftAndResources() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>再読込前</p>")
        defer { harness.stop() }
        try await harness.waitForText("再読込前")
        harness.document.draft = "<p>再読込後の下書き</p>"
        harness.model.reload()
        harness.coordinator.update(harness.webView)
        try await harness.waitForText("再読込後の下書き")
        #expect(harness.document.isDirty)
    }

    @Test
    func saveReloadsResourcesEvenWhenHTMLHasNotChanged() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<link rel='stylesheet' href='style.css'><p>保存する本文</p>", prepare: false)
        defer { harness.stop() }
        let stylesheet = harness.root.appendingPathComponent("style.css")
        try Data("p { color: rgb(12, 34, 56); }".utf8).write(to: stylesheet)
        await harness.start()
        try await harness.waitForText("保存する本文")
        #expect(try await harness.string("getComputedStyle(document.querySelector('p')).color") == "rgb(12, 34, 56)")
        try Data("p { color: rgb(65, 43, 21); }".utf8).write(to: stylesheet)
        #expect(try await harness.document.save() == .saved)
        harness.coordinator.update(harness.webView)
        try await harness.waitForString("getComputedStyle(document.querySelector('p')).color", equals: "rgb(65, 43, 21)")
        #expect(!harness.document.isDirty)
    }

    @Test
    func saveRendersLatestUnsavedDraft() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>保存前の本文</p>")
        defer { harness.stop() }
        try await harness.waitForText("保存前の本文")
        harness.document.draft = "<p>保存後の本文</p>"
        #expect(try await harness.document.save() == .saved)
        harness.coordinator.update(harness.webView)
        try await harness.waitForText("保存後の本文")
        #expect(try String(contentsOf: harness.root.appendingPathComponent("index.html"), encoding: .utf8) == "<p>保存後の本文</p>")
    }

    @Test
    func hoverReportsResolvedLinkFromIsolatedUserScript() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<a href='next.md'><span>次のファイル</span></a>", prepare: false)
        defer { harness.stop() }
        try Data("次の文書".utf8).write(to: harness.root.appendingPathComponent("next.md"))
        await harness.start()
        try await harness.waitForText("次のファイル")
        let before = try await harness.string("document.documentElement.outerHTML")
        _ = try await harness.string("document.querySelector('span').dispatchEvent(new MouseEvent('mouseover', { bubbles: true })); '送信済み'")
        try await harness.waitForDestination(.openFile("next.md"))
        #expect(harness.model.hoveredURL?.absoluteString == "phlox-worktree://local/next.md")
        #expect(try await harness.string("document.documentElement.outerHTML") == before)
        _ = try await harness.string("document.querySelector('span').dispatchEvent(new MouseEvent('mouseout', { bubbles: true })); '送信済み'")
        try await harness.waitForURL(nil)
    }

    @Test
    func focusAndBlurReportBrowserAndUnsupportedLinks() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<a id='browser' href='https://example.invalid/'>ブラウザ</a><a id='unsupported' href='mailto:test@example.invalid'>未対応</a>")
        defer { harness.stop() }
        try await harness.waitForText("ブラウザ")
        _ = try await harness.string("document.querySelector('#browser').focus(); '選択済み'")
        try await harness.waitForDestination(.openBrowser(URL(string: "https://example.invalid/")!))
        _ = try await harness.string("document.querySelector('#unsupported').focus(); '選択済み'")
        try await harness.waitForURL(URL(string: "mailto:test@example.invalid")!)
        #expect(harness.model.hoveredDestination == .cancel)
        _ = try await harness.string("document.querySelector('#unsupported').blur(); '解除済み'")
        try await harness.waitForURL(nil)
    }

    @Test
    func pageScriptsStayDisabledWhileUserScriptReportsLinks() async throws {
        let harness = try await HTMLRuntimeHarness(html: """
        <p id='status'>ページのスクリプトは未実行</p>
        <a href='https://example.invalid/' onmouseover="document.querySelector('#status').textContent = 'イベント実行';">リンク</a>
        <script>document.querySelector('#status').textContent = 'インライン実行';</script>
        <script src='page.js'></script>
        """, prepare: false)
        defer { harness.stop() }
        try Data("document.querySelector('#status').textContent = '外部実行';".utf8)
            .write(to: harness.root.appendingPathComponent("page.js"))
        await harness.start()
        try await harness.waitForText("ページのスクリプトは未実行")
        _ = try await harness.string("document.querySelector('a').dispatchEvent(new MouseEvent('mouseover', { bubbles: true })); '送信済み'")
        try await harness.waitForDestination(.openBrowser(URL(string: "https://example.invalid/")!))
        #expect(!harness.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(try await harness.string("document.querySelector('#status').textContent") == "ページのスクリプトは未実行")
    }

    @Test
    func pageWorldCannotSeeOrSendToHoverHandler() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>実行領域の隔離</p>")
        defer { harness.stop() }
        try await harness.waitForText("実行領域の隔離")
        let probe = "String(!!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.phloxLinkHover))"
        let isolated = try await harness.webView.evaluateJavaScript(probe, in: nil, contentWorld: HTMLLinkHover.world)
        #expect(isolated as? String == "true")
        let page = try await harness.webView.evaluateJavaScript(probe, in: nil, contentWorld: .page)
        #expect(page as? String == "false")
        let send = """
        (() => {
            try {
                window.webkit.messageHandlers.phloxLinkHover.postMessage('https://example.invalid/');
                return '送信できた';
            } catch (error) { return '送信不可'; }
        })()
        """
        let result = try await harness.webView.evaluateJavaScript(send, in: nil, contentWorld: .page)
        #expect(result as? String == "送信不可")
        #expect(harness.model.hoveredURL == nil)
    }

    @Test("iframe のリンクは target を含めクリック時と同じ行き先を表示する",
          arguments: ["", "_self", "_top", "_parent", "_blank", "新しい窓"])
    func frameHoverMatchesClick(target: String) async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>本文</p><iframe id='frame' src='frame.html'></iframe>", prepare: false)
        defer { harness.stop() }
        try Data("<a id='link' href='https://example.invalid/' target='\(target)'>リンク</a>".utf8)
            .write(to: harness.root.appendingPathComponent("frame.html"))
        await harness.start()
        try await harness.waitForText("本文")
        _ = try await harness.string("document.querySelector('#frame').contentDocument.querySelector('#link').dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); '送信済み'")
        try await harness.waitForURL(URL(string: "https://example.invalid/")!)
        let expected = HTMLNavigationPolicy.decide(
            url: URL(string: "https://example.invalid/")!, mainDocumentURL: WorktreeURL.url(for: "index.html")!,
            navigationType: .linkActivated, isMainFrame: ["_top", "_parent"].contains(target),
            hasTargetFrame: !["_blank", "新しい窓"].contains(target), isInitialLoad: false)
        try await harness.waitForDestination(expected)
    }

    @Test("同じ href でも target が変わればホバー判定を更新する")
    func hoverTracksTarget() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<a href='https://example.invalid/' target='_blank'>リンク</a>")
        defer { harness.stop() }
        try await harness.waitForText("リンク")
        _ = try await harness.string("document.querySelector('a').focus(); '選択済み'")
        try await harness.waitForURL(URL(string: "https://example.invalid/")!)
        #expect(harness.model.hoveredDestination == .cancel)
        _ = try await harness.string("document.querySelector('a').target='_self'; document.querySelector('a').dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); '送信済み'")
        try await harness.waitForDestination(.openBrowser(URL(string: "https://example.invalid/")!))
    }

    @Test("入れ子の _parent と既存の名前付きフレームもクリックと同じ判定になる")
    func nestedAndNamedFrameTargets() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>本文</p><iframe id='outer' name='既存フレーム' src='outer.html'></iframe>", prepare: false)
        defer { harness.stop() }
        try Data("<iframe id='inner' src='inner.html'></iframe>".utf8).write(to: harness.root.appendingPathComponent("outer.html"))
        try Data("<a href='https://example.invalid/' target='_parent'>リンク</a>".utf8).write(to: harness.root.appendingPathComponent("inner.html"))
        await harness.start()
        try await harness.waitForText("本文")
        let anchor = "document.querySelector('#outer').contentDocument.querySelector('#inner').contentDocument.querySelector('a')"
        for target in ["_parent", "既存フレーム"] {
            _ = try await harness.string("\(anchor).target='\(target)'; \(anchor).dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); '送信済み'")
            try await harness.waitForURL(URL(string: "https://example.invalid/")!)
            #expect(harness.model.hoveredDestination == .cancel)
        }
    }

    @Test("iframe 内のローカルリンクはホバーどおり iframe 内に開く")
    func localFrameLinkClick() async throws {
        let harness = try await HTMLRuntimeHarness(html: "<p>本文</p><iframe id='frame' src='frame.html'></iframe>", prepare: false)
        defer { harness.stop() }
        try Data("<a href='next.html'>リンク</a>".utf8).write(to: harness.root.appendingPathComponent("frame.html"))
        try Data("<p>移動先</p>".utf8).write(to: harness.root.appendingPathComponent("next.html"))
        await harness.start()
        try await harness.waitForText("本文")
        _ = try await harness.string("document.querySelector('#frame').contentDocument.querySelector('a').dispatchEvent(new MouseEvent('mouseover', {bubbles:true})); '送信済み'")
        try await harness.waitForDestination(.allow)
        _ = try await harness.string("document.querySelector('#frame').contentDocument.querySelector('a').click(); 'クリック済み'")
        try await harness.waitForString("document.querySelector('#frame').contentDocument.body.textContent", equals: "移動先")
        #expect(WorktreeURL.relativePath(try #require(harness.webView.url)) == "index.html")
    }

    @Test("行き先表示を画面に出さず画像へ描ける")
    func destinationLabelRendersOffscreen() throws {
        let labels = ["ページ内で開く  phlox-worktree://local/next.html", "開きません  https://example.invalid/", "このファイル名は表示できません"]
        let content = VStack(alignment: .leading, spacing: 12) {
            ForEach(labels, id: \.self) { text in
                HTMLLinkDestinationLabel(text: text, color: .labelColor)
                    .frame(width: 440, height: 22)
            }
        }.padding(16).background(Color.white).environment(\.colorScheme, .light)
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 130)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(bitmap.pixelsWide >= 480)
        #expect(bitmap.pixelsHigh >= 130)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: package.appendingPathComponent(".build/html-review-labels.png"))
    }

}

/// 製品の WebView をそのままウィンドウに載せ、公開 API だけで表示を観測する。
@MainActor
final class HTMLRuntimeHarness {
    let root: URL
    let document: FileTabDocument
    let model: HTMLPreviewModel
    let coordinator: HTMLPreviewView.Coordinator
    let webView: WKWebView
    let window: NSWindow

    init(html: String, prepare: Bool = true) async throws {
        _ = NSApplication.shared
        root = try makeFileTabTestRoot()
        try Data(html.utf8).write(to: root.appendingPathComponent("index.html"))
        document = FileTabDocument(path: "index.html", root: root.path)
        await document.loadIfNeeded()
        model = HTMLPreviewModel(document: document)
        coordinator = HTMLPreviewView.Coordinator(model: model, openFile: { _ in })
        webView = coordinator.makeWebView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        // テストのウィンドウは画面に出さない。
        if prepare { await start() }
    }

    func start() async {
        await model.prepare()
        coordinator.update(webView)
    }

    func stop() {
        coordinator.stop()
        window.close()
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("HTML テスト用ディレクトリを削除できません: \(error)") }
    }

    func waitForText(_ text: String) async throws {
        try await Self.waitForText(text, in: webView)
    }

    static func waitForText(_ text: String, in webView: WKWebView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            let found = await withCheckedContinuation { continuation in
                webView.find(text, configuration: WKFindConfiguration()) {
                    continuation.resume(returning: $0.matchFound)
                }
            }
            if found && !webView.isLoading { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw RuntimeError.textNotRendered(text)
    }

    /// ページ由来のスクリプトは無効のまま、別の実行領域で DOM を読み取る。
    func string(_ script: String) async throws -> String {
        let value = try await webView.evaluateJavaScript(script, in: nil, contentWorld: .defaultClient)
        return try #require(value as? String)
    }

    func waitForString(_ script: String, equals expected: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if try await string(script) == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw RuntimeError.valueNotRendered(expected)
    }

    func waitForDestination(_ expected: HTMLNavigationPolicy.Decision) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if model.hoveredDestination == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw RuntimeError.valueNotRendered(String(describing: expected))
    }

    func waitForURL(_ expected: URL?) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if model.hoveredURL == expected { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw RuntimeError.valueNotRendered(String(describing: expected))
    }

    enum RuntimeError: Error {
        case textNotRendered(String)
        case valueNotRendered(String)
    }
}
