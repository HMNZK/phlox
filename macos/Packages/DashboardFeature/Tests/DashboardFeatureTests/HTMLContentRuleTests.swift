import Foundation
import Testing
@testable import DashboardFeature

struct HTMLContentRuleTests {
    @Test
    func permitsOnlyWorktreeScheme() throws {
        let rules = try #require(JSONSerialization.jsonObject(with: Data(HTMLContentRules.json.utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        let block = try #require(rules.first)
        #expect((block["action"] as? [String: String])?["type"] == "block")
        #expect((block["trigger"] as? [String: String])?["url-filter"] == ".*")
        let allow = try #require(rules.last)
        #expect((allow["action"] as? [String: String])?["type"] == "ignore-previous-rules")
        let filter = try #require((allow["trigger"] as? [String: String])?["url-filter"])
        for url in ["phlox-worktree://local/docs/a.html", "phlox-worktree://local/style.css"] {
            #expect(url.range(of: filter, options: .regularExpression) != nil)
        }
        for url in ["https://example.invalid/a.png", "http://127.0.0.1/a", "file:///tmp/a", "data:text/html,abc",
                    "phlox-worktree://outside/a", "https://example.invalid/phlox-worktree://local/a"] {
            #expect(url.range(of: filter, options: .regularExpression) == nil)
        }
    }

    @Test @MainActor
    func supportedMarkupDefaultsToRendered() {
        for path in ["a.html", "a.htm", "a.HTML"] {
            let document = FileTabDocument(path: path, root: "/")
            #expect(document.isHTML)
            #expect(document.presentation == .rendered)
        }
        // 出荷単位 4 の FR-8: マークダウンも描画表示で開く。
        for path in ["a.md", "a.markdown", "a.MD"] {
            let document = FileTabDocument(path: path, root: "/")
            #expect(!document.isHTML)
            #expect(document.isMarkdown)
            #expect(document.presentation == .rendered)
        }
        for path in ["a.txt", "a.swift"] {
            let document = FileTabDocument(path: path, root: "/")
            #expect(!document.isHTML)
            #expect(document.presentation == .source)
        }
    }

    @Test @MainActor
    func unsupportedPathKeepsSourceBeforeCompilation() async {
        let document = FileTabDocument(path: "%2e.html", root: "/")
        let model = HTMLPreviewModel(document: document)
        var compiled = false
        await model.prepare(compile: {
            compiled = true
            throw URLError(.cannotLoadFromNetwork)
        })
        #expect(!compiled)
        #expect(document.presentation == .source)
        #expect(model.ruleList == nil)
        #expect(model.preparationError == "このファイル名は表示できません")
        #expect(model.preparationFailureReason == "このファイル名は表示できません")
    }
}
