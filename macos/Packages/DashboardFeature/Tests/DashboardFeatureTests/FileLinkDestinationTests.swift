import Foundation
import Testing
@testable import DashboardFeature

struct FileLinkDestinationTests {
    @Test("作業ツリーの URL は内部スキームを出さず日本語と空白を含むパスへ戻す")
    func worktreePath() throws {
        let url = try #require(WorktreeURL.url(for: "docs/使い方 と設定.md"))
        let destination = FileLinkDestination(url: url, decision: .openFile("docs/使い方 と設定.md"))
        #expect(destination.path == "docs/使い方 と設定.md")
    }

    @Test("アンカーとクエリは相対パスの後ろに残す")
    func worktreeAnchorAndQuery() throws {
        let url = try #require(URL(string: "phlox-worktree://local/docs/index.html?name=a%20b#title"))
        let destination = FileLinkDestination(url: url, decision: .allow)
        #expect(destination.path == "docs/index.html?name=a%20b#title")
    }

    @Test("外部と対象外の行き先は URL を省かない", arguments: ["https://example.invalid/a?name=x#title", "mailto:user@example.invalid"])
    func externalDestination(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(FileLinkDestination(url: url, decision: .cancel).path == address)
    }
}
