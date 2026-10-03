import Foundation

enum MarkdownLinkRouting {
    static func resolvedURL(_ link: URL, documentPath: String, root: String) -> URL? {
        if link.isFileURL {
            guard let path = FileTabOpening.relativePath(of: link, under: root) else { return nil }
            return WorktreeURL.url(for: path)
        }
        guard link.scheme == nil else { return link }
        guard let base = WorktreeURL.url(for: documentPath) else { return nil }
        guard link.host == nil else { return nil }
        var depth = link.path.hasPrefix("/") ? 0 : documentPath.split(separator: "/").count - 1
        for part in link.path.split(separator: "/") {
            if part == ".." {
                guard depth > 0 else { return nil }
                depth -= 1
            } else if part != "." { depth += 1 }
        }
        return URL(string: link.relativeString, relativeTo: base)?.absoluteURL.standardized
    }

    static func destination(_ link: URL, documentPath: String, root: String) -> HTMLNavigationPolicy.Decision {
        guard let url = resolvedURL(link, documentPath: documentPath, root: root) else { return .cancel }
        return HTMLNavigationPolicy.linkDestination(url)
    }

    /// 描画後にもクリック時にも、共通の読み取り経路で実パスを検査する。
    static func checkedDestination(_ link: URL, documentPath: String, root: String) async -> HTMLNavigationPolicy.Decision {
        let decision = destination(link, documentPath: documentPath, root: root)
        if case .openFile(let path) = decision {
            let service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root), fixedRoot: true)
            guard await service.absolutePath(path) != nil else { return .cancel }
        }
        return decision
    }
}
