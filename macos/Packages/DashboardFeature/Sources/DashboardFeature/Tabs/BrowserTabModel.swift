import AppKit
import Foundation
import Observation
import WebKit

enum BrowserAddress {
    static func url(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") || text.hasPrefix("~/") {
            let parts = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let path = (String(parts[0]) as NSString).expandingTildeInPath
            var components = URLComponents(url: URL(fileURLWithPath: path), resolvingAgainstBaseURL: false)
            if parts.count == 2 { components?.fragment = String(parts[1]) }
            return components?.url
        }
        let hasScheme = text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        guard let url = URL(string: hasScheme ? text : "https://\(text)"),
              let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "file" {
            guard url.host == nil || url.host == "" || url.host == "localhost", url.path.hasPrefix("/") else { return nil }
            return url
        }
        guard ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }), url.user == nil, url.password == nil else { return nil }
        // mailto: などをホスト名として誤って補完しない。
        if !hasScheme, text.contains(":"), URLComponents(url: url, resolvingAgainstBaseURL: false)?.port == nil { return nil }
        return url
    }

    static func allowsNavigation(to url: URL, readAccess: URL?) -> Bool {
        if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { return true }
        guard url.isFileURL, let readAccess else { return false }
        let root = readAccess.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root == "/" ? root : root + "/")
    }
}

@MainActor @Observable
final class BrowserTabModel: NSObject, WKNavigationDelegate, WKUIDelegate {
    var url: URL?
    var title = ""
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var error: String?
    private(set) var readAccess: URL?
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var panels: Set<NSWindow> = []
    @ObservationIgnored private var navigationPending = false
    @ObservationIgnored private var explicitNavigationURL: URL?
    @ObservationIgnored private var pendingReadAccess: URL?

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsLinkPreview = false
        view.setAccessibilityLabel(String(localized: "ブラウザのページ"))
        webView = view
        observations = [
            view.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            view.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            view.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            view.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            view.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.updateState() } }
        ]
        if let url { load(url) }
        return view
    }

    func submit(_ address: String) {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let url = BrowserAddress.url(from: address) else {
            error = String(localized: "URL またはファイルの絶対パスを入力してください。")
            return
        }
        open(url)
    }

    func open(_ url: URL) {
        guard url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        error = nil
        title = ""
        isLoading = true
        self.url = url
        pendingReadAccess = url.isFileURL ? url.deletingLastPathComponent().resolvingSymlinksInPath() : nil
        if webView != nil { load(url) }
    }

    private func load(_ url: URL, request: URLRequest? = nil) {
        guard let webView else { return }
        navigationPending = true
        explicitNavigationURL = url
        if url.isFileURL, let readAccess = pendingReadAccess {
            webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        } else {
            webView.load(request ?? URLRequest(url: url))
        }
    }

    func back() {
        navigate(to: webView?.backForwardList.backItem)
    }
    func forward() {
        navigate(to: webView?.backForwardList.forwardItem)
    }
    private func navigate(to item: WKBackForwardListItem?) {
        guard let webView, let item else { return }
        error = nil
        navigationPending = true
        url = item.url
        explicitNavigationURL = item.url
        pendingReadAccess = readAccessForNavigation(to: item.url)
        webView.go(to: item)
    }
    func reloadOrStop() {
        if isLoading {
            webView?.stopLoading()
            navigationPending = false
            explicitNavigationURL = nil
            isLoading = false
        } else if error != nil, let url {
            error = nil
            isLoading = true
            pendingReadAccess = readAccessForNavigation(to: url)
            load(url)
        } else {
            navigationPending = true
            explicitNavigationURL = webView?.url
            pendingReadAccess = readAccess
            webView?.reload()
        }
    }

    func close() {
        for panel in panels { panel.sheetParent?.endSheet(panel, returnCode: .cancel) }
        panels.removeAll()
        observations.removeAll()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        pendingReadAccess = nil
        navigationPending = false
        explicitNavigationURL = nil
        isLoading = false
    }

    private func updateState() {
        guard let webView else { return }
        isLoading = webView.isLoading
        title = webView.title ?? ""
        if !webView.isLoading, webView.url == url { navigationPending = false }
        if !navigationPending, error == nil, let current = webView.url { url = current }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        readAccess = pendingReadAccess
        explicitNavigationURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationPending = false
        updateState()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ failure: Error) {
        let failure = failure as NSError
        guard !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) else { return }
        navigationPending = false
        explicitNavigationURL = nil
        isLoading = false
        // ダウンロード等を拒否した際の通知で、既に表示した理由を上書きしない。
        guard !(failure.domain == "WebKitErrorDomain" && failure.code == 102) else { return }
        error = failure.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        navigationPending = false
        explicitNavigationURL = nil
        error = String(localized: "ページの表示が停止しました。再読込してください。")
    }

    private func allows(_ action: WKNavigationAction, in webView: WKWebView) -> Bool {
        guard let url = action.request.url else { return false }
        let isMainFrame = action.targetFrame?.isMainFrame != false
        if !isMainFrame, ["about", "data", "blob"].contains(url.scheme?.lowercased() ?? "") { return true }
        if isMainFrame, url.isFileURL, explicitNavigationURL != url,
           [action.sourceFrame.request.url, webView.url].contains(where: {
               ["http", "https"].contains($0?.scheme?.lowercased() ?? "")
           }) { return false }
        return BrowserAddress.allowsNavigation(to: url, readAccess: explicitNavigationURL == url ? pendingReadAccess : readAccess)
    }

    private func readAccessForNavigation(to url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        if BrowserAddress.allowsNavigation(to: url, readAccess: readAccess) { return readAccess }
        return url.deletingLastPathComponent().resolvingSymlinksInPath()
    }

    private func prepareNavigation(to url: URL) {
        navigationPending = true
        self.url = url
        if explicitNavigationURL != url { pendingReadAccess = readAccessForNavigation(to: url) }
        explicitNavigationURL = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload {
            if action.targetFrame?.isMainFrame != false {
                error = String(localized: "ダウンロードには対応していません。")
                navigationPending = false
                explicitNavigationURL = nil
                isLoading = false
            }
            decisionHandler(.cancel)
            return
        }
        guard let url = action.request.url, allows(action, in: webView) else {
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame?.isMainFrame != false { prepareNavigation(to: url) }
        if action.targetFrame == nil {
            decisionHandler(.cancel)
            load(url, request: action.request)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        guard response.canShowMIMEType, !disposition.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("attachment") else {
            if response.isForMainFrame {
                error = String(localized: "ダウンロードには対応していません。")
                navigationPending = false
                explicitNavigationURL = nil
                isLoading = false
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if !action.shouldPerformDownload, let url = action.request.url, allows(action, in: webView) {
            prepareNavigation(to: url)
            load(url, request: action.request)
        }
        return nil
    }

    private func alert(_ message: String, frame: WKFrameInfo) -> NSAlert {
        let panel = NSAlert()
        panel.messageText = frame.request.url?.host ?? frame.request.url?.lastPathComponent ?? String(localized: "ページからのメッセージ")
        panel.informativeText = message
        panel.addButton(withTitle: "OK")
        return panel
    }

    private func present(_ alert: NSAlert, on window: NSWindow,
                         completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void) {
        panels.insert(alert.window)
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.panels.remove(alert.window)
            completion(response)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        guard let window = webView.window else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            present(alert(message, frame: frame), on: window) { _ in continuation.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard let window = webView.window else { return false }
        let panel = alert(message, frame: frame)
        panel.addButton(withTitle: String(localized: "キャンセル"))
        return await withCheckedContinuation { continuation in
            present(panel, on: window) { response in continuation.resume(returning: response == .alertFirstButtonReturn) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard let window = webView.window else { return nil }
        let panel = alert(prompt, frame: frame)
        panel.addButton(withTitle: String(localized: "キャンセル"))
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        panel.accessoryView = input
        return await withCheckedContinuation { continuation in
            present(panel, on: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn ? input.stringValue : nil)
            }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        guard let window = webView.window else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panels.insert(panel)
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.panels.remove(panel)
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}
