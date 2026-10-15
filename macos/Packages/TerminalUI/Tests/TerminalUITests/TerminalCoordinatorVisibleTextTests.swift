import Testing
import Foundation
@testable import TerminalUI

@MainActor
struct TerminalCoordinatorVisibleTextTests {
    @Test("VoiceOver の行内の空セルは空白にし、全角文字の後続セルは除く", arguments: [
        ("A\u{1b}[5GB", "A   B"), ("日\u{1b}[5GB", "日  B"), ("A\tB", "A       B")
    ])
    func accessibilityBlankCells(_ values: (String, String)) throws {
        let coordinator = TerminalCoordinator()
        coordinator.terminalView.resize(cols: 20, rows: 2)
        coordinator.feed(Data(values.0.utf8))
        let value = try #require(coordinator.terminalView.accessibilityValue() as? String)
        #expect(value.components(separatedBy: "\n").first == values.1)
        #expect(!value.contains("\0"))
    }

    @Test
    func visibleText_afterFeed_containsWrittenText() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("Hello".utf8))
        #expect(coordinator.visibleText().contains("Hello"))
    }

    @Test
    func visibleText_onFreshCoordinator_isEmpty() {
        let coordinator = TerminalCoordinator()
        #expect(coordinator.visibleText() == "")
    }

    @Test("全角文字の後続セルは空白にせず、実際の空白と明示改行を保つ")
    func wideCharactersPreserveActualWhitespace() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("[シェルを開始できませんでした]\r\nhello 日本語  ＡＢ end".utf8))
        #expect(coordinator.visibleText() == "[シェルを開始できませんでした]\nhello 日本語  ＡＢ end")
        #expect(coordinator.visibleText(joinWrappedRows: true) == coordinator.visibleText())
    }

    @Test("全角文字のソフトラップを連結しても、境界の実際の空白を保つ")
    func wideCharactersAtWrapBoundary() {
        let coordinator = TerminalCoordinator()
        coordinator.terminalView.resize(cols: 10, rows: 3)
        coordinator.feed(Data("日本語Ａ  Ｂ end\r\n次".utf8))
        #expect(coordinator.visibleText() == "日本語Ａ\nＢ end\n次")
        #expect(coordinator.visibleText(joinWrappedRows: true) == "日本語Ａ  Ｂ end\n次")
    }
}
