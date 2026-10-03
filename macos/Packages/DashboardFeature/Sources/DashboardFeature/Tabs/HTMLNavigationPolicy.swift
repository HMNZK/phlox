import Foundation
import WebKit

enum WorktreeURL {
    static func url(for path: String) -> URL? {
        guard validPath(path) else { return nil }
        var components = URLComponents()
        components.scheme = "phlox-worktree"
        components.host = "local"
        components.path = "/" + path
        return components.url
    }

    static func relativePath(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme == "phlox-worktree", components.host == "local",
              components.user == nil, components.password == nil, components.port == nil,
              let path = components.percentEncodedPath.removingPercentEncoding,
              path.hasPrefix("/") else { return nil }
        let relativePath = String(path.dropFirst())
        return validPath(relativePath) ? relativePath : nil
    }

    private static func validPath(_ path: String) -> Bool {
        // 二重符号化を拒否する。「100%.html」のような裸の % はファイル名として許す。
        path.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) == nil
            && (try? WorkingTreeService.relativeURL(for: path, relativeTo: URL(fileURLWithPath: "/"))) != nil
    }
}

enum HTMLNavigationPolicy {
    enum Decision: Equatable {
        case allow
        case cancel
        case openFile(String)
        case openBrowser(URL)
    }

    static func decide(url: URL, mainDocumentURL: URL, navigationType: WKNavigationType, isMainFrame: Bool, hasTargetFrame: Bool, isInitialLoad: Bool) -> Decision {
        guard hasTargetFrame, navigationType != .formSubmitted, navigationType != .formResubmitted else { return .cancel }
        let isWorktreeURL = WorktreeURL.relativePath(url) != nil
        if !isMainFrame { return isWorktreeURL ? .allow : .cancel }
        if isWorktreeURL, sameDocument(url, mainDocumentURL), isInitialLoad || url.fragment != nil {
            return .allow
        }
        guard navigationType == .linkActivated else { return .cancel }
        return linkDestination(url)
    }

    static func linkDestination(_ url: URL) -> Decision {
        if let path = WorktreeURL.relativePath(url), ["md", "markdown", "html", "htm"].contains((path as NSString).pathExtension.lowercased()) {
            return .openFile(path)
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty {
            return .openBrowser(url)
        }
        return .cancel
    }

    private static func sameDocument(_ first: URL, _ second: URL) -> Bool {
        var first = URLComponents(url: first, resolvingAgainstBaseURL: true)
        var second = URLComponents(url: second, resolvingAgainstBaseURL: true)
        first?.fragment = nil
        second?.fragment = nil
        return first != nil && first == second
    }
}
