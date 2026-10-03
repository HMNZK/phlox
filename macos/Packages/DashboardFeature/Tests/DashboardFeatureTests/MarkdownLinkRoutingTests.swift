import Foundation
import Testing
@testable import DashboardFeature

@Suite("マークダウンのリンクの行き先")
struct MarkdownLinkRoutingTests {
    @Test("文書の位置を基準に対応ファイルを解決する", arguments: ["md", "markdown", "html", "htm"])
    func relativeLinks(ext: String) {
        #expect(destination("../guide.\(ext)") == .openFile("guide.\(ext)"))
        #expect(destination("next.\(ext)#section") == .openFile("docs/next.\(ext)"))
        #expect(destination("/guide.\(ext)") == .openFile("guide.\(ext)"))
    }

    @Test("外部リンクと開けないリンクを区別する")
    func rejectedLinks() {
        let https = URL(string: "https://example.invalid/guide")!
        #expect(destination(https.absoluteString) == .openBrowser(https))
        #expect(destination("http://example.invalid/") == .openBrowser(URL(string: "http://example.invalid/")!))
        for link in ["../../outside.md", "image.png", "mailto:a@example.invalid", "file:///elsewhere/a.md", "phlox-worktree://other/a.md", "../%252e%252e/a.md"] {
            #expect(destination(link) == .cancel)
        }
        #expect(destination("file:///work/docs/guide.md") == .openFile("docs/guide.md"))
    }

    @Test("ルート外へのシンボリックリンクはホバーとクリックで開かない")
    func symlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try Data("外側".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: outside)
        #expect(await MarkdownLinkRouting.checkedDestination(URL(string: "link.md")!, documentPath: "index.md", root: root.path) == .cancel)
    }

    private func destination(_ link: String) -> HTMLNavigationPolicy.Decision {
        MarkdownLinkRouting.destination(URL(string: link)!, documentPath: "docs/index.md", root: "/work")
    }
}
