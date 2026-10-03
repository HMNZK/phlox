import Foundation
import Testing
import WebKit
@testable import DashboardFeature

@Suite("HTML の遷移判定")
struct HTMLNavigationPolicyTests {
    private let document = URL(string: "phlox-worktree://local/docs/index.html")!

    @Test("初回読み込みと同一文書のアンカーだけメインフレームで許可する")
    func initialLoadAndAnchor() {
        #expect(decide(document, initial: true) == .allow)
        #expect(decide(document) == .cancel)
        #expect(decide(URL(string: "phlox-worktree://local/docs/index.html#title")!) == .allow)
        #expect(decide(URL(string: "phlox-worktree://local/docs/other.html#title")!) == .cancel)
        #expect(decide(URL(string: "https://example.invalid/")!, initial: true) == .cancel)
    }

    @Test("クリックされた対応ファイルだけファイルタブへ渡す", arguments: ["guide.md", "guide.markdown", "guide.html", "guide.HTM"])
    func fileLinks(path: String) {
        let url = URL(string: "phlox-worktree://local/docs/\(path)")!
        #expect(decide(url, type: .linkActivated) == .openFile("docs/\(path)"))
        #expect(decide(url) == .cancel)
        #expect(HTMLNavigationPolicy.linkDestination(url) == .openFile("docs/\(path)"))
    }

    @Test("外部リンクはユーザーのクリックだけブラウザへ渡す", arguments: ["http://example.invalid/a", "https://example.invalid/a"])
    func externalLinks(address: String) {
        let url = URL(string: address)!
        #expect(decide(url, type: .linkActivated) == .openBrowser(url))
        for type: WKNavigationType in [.other, .formSubmitted, .formResubmitted, .reload, .backForward] {
            #expect(decide(url, type: type) == .cancel)
        }
    }

    @Test("サブフレームは作業フォルダ内の URL だけ許可する")
    func subframes() {
        #expect(decide(URL(string: "phlox-worktree://local/embed.svg")!, main: false) == .allow)
        for address in ["https://example.invalid/", "file:///tmp/a.html", "data:text/html,hello", "phlox-worktree://other/a.html", "phlox-worktree://local/%2e%2e/a.html"] {
            #expect(decide(URL(string: address)!, main: false) == .cancel)
        }
    }

    @Test("新規ウィンドウ・フォーム・対象外のスキームと拡張子は開かない")
    func unsupportedNavigation() {
        let external = URL(string: "https://example.invalid/")!
        #expect(decide(external, type: .linkActivated, target: false) == .cancel)
        #expect(decide(document, type: .linkActivated, target: false, initial: true) == .cancel)
        #expect(decide(document, type: .formSubmitted) == .cancel)
        #expect(decide(URL(string: "phlox-worktree://local/docs/index.html#title")!, type: .formSubmitted) == .cancel)
        for address in ["mailto:someone@example.invalid", "javascript:alert(1)", "file:///tmp/a.html", "phlox-worktree://local/a.txt"] {
            #expect(decide(URL(string: address)!, type: .linkActivated) == .cancel)
        }
    }

    private func decide(_ url: URL, type: WKNavigationType = .other, main: Bool = true, target: Bool = true, initial: Bool = false) -> HTMLNavigationPolicy.Decision {
        HTMLNavigationPolicy.decide(url: url, mainDocumentURL: document, navigationType: type, isMainFrame: main, hasTargetFrame: target, isInitialLoad: initial)
    }
}
