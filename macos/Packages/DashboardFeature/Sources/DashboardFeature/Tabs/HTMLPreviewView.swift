import AppKit
import SwiftUI
import Observation
import WebKit

enum HTMLContentRules {
    // 全要求を止め、作業フォルダの独自スキームだけを許可する。
    static let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^phlox-worktree://local/"},"action":{"type":"ignore-previous-rules"}}]"#

    @MainActor
    static func compile() async throws -> WKContentRuleList {
        guard let rules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "phlox-html-worktree-only-v1", encodedContentRuleList: json
        ) else { throw URLError(.cannotLoadFromNetwork) }
        return rules
    }
}

@MainActor
@Observable
final class HTMLPreviewModel {
    let document: FileTabDocument
    private(set) var ruleList: WKContentRuleList?
    private(set) var preparationError: String?
    private(set) var processTerminated = false
    var preparationFailureReason: String {
        WorktreeURL.url(for: document.path) == nil
            ? "このファイル名は表示できません" : "プレビューを出せません（安全の準備に失敗）"
    }
    var revision: Int { document.htmlPreviewRevision }
    var hoveredURL: URL?
    var hoveredDestination: HTMLNavigationPolicy.Decision = .cancel
    @ObservationIgnored private var preparing = false

    init(document: FileTabDocument) { self.document = document }

    func prepare(compile: () async throws -> WKContentRuleList = { try await HTMLContentRules.compile() }) async {
        guard ruleList == nil, preparationError == nil, !preparing else { return }
        preparing = true
        defer { preparing = false }
        guard WorktreeURL.url(for: document.path) != nil else {
            stopWithPreparationError("このファイル名は表示できません")
            return
        }
        do {
            let rules = try await compile()
            guard !document.invalidated, preparationError == nil else { return }
            ruleList = rules
        } catch {
            stopWithPreparationError(error.localizedDescription)
        }
    }

    func stopWithPreparationError(_ message: String) {
        ruleList = nil
        preparationError = message
        document.presentation = .source
    }

    func reload() {
        processTerminated = false
        hoveredURL = nil
        document.reloadHTMLPreview()
    }

    func didTerminate() { processTerminated = true }

    func hover(_ url: URL?, target: String = "", isMainFrame: Bool = true, parentIsMainFrame: Bool = true, namedTargetIsMainFrame: Bool? = nil) async {
        hoveredURL = url
        hoveredDestination = .cancel
        guard let url else { return }
        guard let mainURL = WorktreeURL.url(for: document.path) else { return }
        let targetsMainFrame: Bool
        let hasTargetFrame: Bool
        switch target.lowercased() {
        case "", "_self": (targetsMainFrame, hasTargetFrame) = (isMainFrame, true)
        case "_top": (targetsMainFrame, hasTargetFrame) = (true, true)
        case "_parent": (targetsMainFrame, hasTargetFrame) = (parentIsMainFrame, true)
        default: (targetsMainFrame, hasTargetFrame) = (namedTargetIsMainFrame ?? false, namedTargetIsMainFrame != nil)
        }
        let destination = HTMLNavigationPolicy.decide(
            url: url, mainDocumentURL: mainURL, navigationType: .linkActivated,
            isMainFrame: targetsMainFrame, hasTargetFrame: hasTargetFrame, isInitialLoad: false
        )
        if case .openFile(let path) = destination {
            let service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: document.root), fixedRoot: true)
            guard await service.absolutePath(path) != nil, hoveredURL == url else { return }
        }
        guard hoveredURL == url, !Task.isCancelled else { return }
        hoveredDestination = destination
    }
}

/// ページとは別の実行領域で、リンクの行き先だけを読み取る。
@MainActor
enum HTMLLinkHover {
    static let world = WKContentWorld.world(name: "phlox-html-link-hover")
    static let messageName = "phloxLinkHover"
    static let source = """
    (() => {
        let hovered = null;
        let focused = null;
        let lastURL = null;
        let lastTarget = null;
        const link = target => target instanceof Element ? target.closest('a[href]') : null;
        const namedFrame = (frame, name) => {
            if (frame.name === name) return frame;
            for (let index = 0; index < frame.frames.length; index++) {
                const found = namedFrame(frame.frames[index], name);
                if (found) return found;
            }
            return null;
        };
        const report = () => {
            const anchor = hovered || focused;
            const url = anchor ? anchor.href : null;
            const target = anchor ? (anchor.target || document.querySelector('base[target]')?.target || '') : '';
            if (url === lastURL && target === lastTarget) return;
            lastURL = url;
            lastTarget = target;
            const frame = target && !['', '_self', '_top', '_parent', '_blank'].includes(target.toLowerCase()) ? namedFrame(window.top, target) : null;
            window.webkit.messageHandlers.phloxLinkHover.postMessage({
                href: url, target, parentIsMainFrame: window.parent === window.top,
                namedTargetIsMainFrame: frame ? frame === window.top : null
            });
        };
        document.addEventListener('mouseover', event => { hovered = link(event.target); report(); });
        document.addEventListener('mouseout', event => { hovered = link(event.relatedTarget); report(); });
        document.addEventListener('focus', event => { focused = link(event.target); report(); }, true);
        document.addEventListener('blur', event => { focused = link(event.relatedTarget); report(); }, true);
    })();
    """
}

@MainActor
private final class HTMLLinkHoverHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message)
    }
}

final class HTMLWebView: WKWebView {
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

/// macOS の静的テキストに、行き先を読み上げ名として公開する。
struct HTMLLinkDestinationLabel: NSViewRepresentable {
    let text: String
    let color: NSColor

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateNSView(label, context: context)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        label.stringValue = text
        label.textColor = color
        label.setAccessibilityLabel(text)
        label.setAccessibilityTitle(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: size.height)
    }
}

struct HTMLPreviewView: NSViewRepresentable {
    let model: HTMLPreviewModel
    var openFile: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model, openFile: openFile) }
    func makeNSView(context: Context) -> HTMLWebView { context.coordinator.makeWebView() }
    func updateNSView(_ webView: HTMLWebView, context: Context) {
        context.coordinator.openFile = openFile
        context.coordinator.update(webView)
    }
    static func dismantleNSView(_ webView: HTMLWebView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: HTMLPreviewModel
        var openFile: (String) -> Void
        private var handler: WorktreeSchemeHandler?
        private weak var webView: WKWebView?
        private var revision: Int?
        private var draftBytes: Data?
        private var initialLoadPending = false
        private var hoverTask: Task<Void, Never>?

        init(model: HTMLPreviewModel, openFile: @escaping (String) -> Void) {
            self.model = model
            self.openFile = openFile
        }

        func makeWebView() -> HTMLWebView {
            let document = model.document
            let handler = WorktreeSchemeHandler(root: document.root, documentPath: document.path, draft: document.draft)
            self.handler = handler
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(handler, forURLScheme: "phlox-worktree")
            let hoverHandler = HTMLLinkHoverHandler()
            hoverHandler.onMessage = { [weak self] message in
                guard let self, message.webView === self.webView, !self.model.document.invalidated else { return }
                guard let body = message.body as? [String: Any], let target = body["target"] as? String else { return }
                let url = (body["href"] as? String).flatMap(URL.init(string:))
                let isMainFrame = message.frameInfo.isMainFrame
                let parentIsMainFrame = body["parentIsMainFrame"] as? Bool ?? false
                let namedTargetIsMainFrame = body["namedTargetIsMainFrame"] as? Bool
                self.hoverTask?.cancel()
                self.hoverTask = Task {
                    guard !Task.isCancelled else { return }
                    await self.model.hover(url, target: target, isMainFrame: isMainFrame,
                                          parentIsMainFrame: parentIsMainFrame, namedTargetIsMainFrame: namedTargetIsMainFrame)
                }
            }
            configuration.userContentController.add(hoverHandler, contentWorld: HTMLLinkHover.world, name: HTMLLinkHover.messageName)
            configuration.userContentController.addUserScript(WKUserScript(
                source: HTMLLinkHover.source, injectionTime: .atDocumentEnd,
                forMainFrameOnly: false, in: HTMLLinkHover.world
            ))
            let webView = HTMLWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsLinkPreview = false
            webView.setAccessibilityLabel("\(document.fileName) のプレビュー（閲覧のみ）")
            self.webView = webView
            update(webView)
            return webView
        }

        func update(_ webView: WKWebView) {
            let document = model.document
            guard !document.invalidated, document.isLoaded, document.presentation == .rendered,
                  let rules = model.ruleList, model.preparationError == nil else {
                webView.stopLoading()
                handler?.stopAll()
                return
            }
            let bytes = Data(document.draft.utf8)
            guard revision != model.revision || draftBytes != bytes else { return }
            guard let url = WorktreeURL.url(for: document.path) else { return }
            hoverTask?.cancel()
            model.hoveredURL = nil
            model.hoveredDestination = .cancel
            webView.stopLoading()
            handler?.stopAll()
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(rules)
            handler?.updateDraft(document.draft)
            revision = model.revision
            draftBytes = bytes
            initialLoadPending = true
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }

        func stop() {
            hoverTask?.cancel()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: HTMLLinkHover.messageName, contentWorld: HTMLLinkHover.world)
            webView?.configuration.userContentController.removeAllUserScripts()
            model.hoveredURL = nil
            model.hoveredDestination = .cancel
            webView?.stopLoading()
            handler?.stopAll()
            webView?.navigationDelegate = nil
            webView?.uiDelegate = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let mainURL = WorktreeURL.url(for: model.document.path),
                  !action.shouldPerformDownload else { decisionHandler(.cancel); return }
            let initial = initialLoadPending
            if action.targetFrame?.isMainFrame == true { initialLoadPending = false }
            let decision = HTMLNavigationPolicy.decide(
                url: url, mainDocumentURL: mainURL, navigationType: action.navigationType,
                isMainFrame: action.targetFrame?.isMainFrame == true,
                hasTargetFrame: action.targetFrame != nil, isInitialLoad: initial
            )
            switch decision {
            case .allow: decisionHandler(.allow)
            case .cancel: decisionHandler(.cancel)
            case .openBrowser(let url):
                decisionHandler(.cancel)
                NSWorkspace.shared.open(url)
            case .openFile(let path):
                decisionHandler(.cancel)
                let root = model.document.root
                Task { [weak self] in
                    let service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root), fixedRoot: true)
                    guard await service.absolutePath(path) != nil, let self, !self.model.document.invalidated else { return }
                    self.openFile(path)
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { model.didTerminate() }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) { completionHandler(nil) }
    }
}
