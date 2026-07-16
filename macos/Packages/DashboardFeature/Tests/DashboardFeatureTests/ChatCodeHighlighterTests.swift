import Testing
import SwiftUI
@testable import DashboardFeature
@testable import SessionFeature

@Suite("ChatCodeHighlighter")
struct ChatCodeHighlighterTests {

    @Test
    func commentLineHasColoredRun() {
        let out = ChatCodeHighlighter.highlight("// comment")
        let hasColoredRun = out.runs.contains { $0.foregroundColor != nil }
        #expect(hasColoredRun)
    }

    @Test
    func numberLiteralHasColoredRun() {
        let out = ChatCodeHighlighter.highlight("let n = 42")
        let coloredRunCount = out.runs.filter { $0.foregroundColor != nil }.count
        #expect(coloredRunCount >= 2)
    }
}
