import PhloxCore
import SwiftUI
import Testing
@testable import TerminalScreenIOS

#if canImport(AppKit)
import AppKit

/// 端末描画の高さは中身が決める（→ ADR 0039）。
/// 守る不具合: 高さを固定すると枠より高い中身の下半分が切れて「上半分しか表示されない」。
/// パーサのテストが全部 green のまま画面だけが切れるので、実際に描いた高さで見る。
@Suite("端末描画の高さ")
@MainActor
struct TerminalScreenHeightTests {

    @Test("行数が増えた分だけ高さも増える（固定高さで頭打ちにならない）")
    func heightGrowsWithLineCount() {
        let short = Self.renderedHeight(lines: 20)
        let long = Self.renderedHeight(lines: 100)

        // 1 行は 10pt を下回らない（12pt の等幅フォント）。増えた 80 行ぶんの高さが全部残ること。
        #expect(long - short >= 80 * 10, "short=\(short) long=\(long)")
    }

    /// 端末画面を実際にホストしてレイアウトを確定させ、中身が要求する高さを返す。
    /// 縦スクロールの親（SessionDetailView）と同じく高さは提案しない。
    /// 行は onChange で組み立てられるので、ウィンドウに載せて数回レイアウトを回す。
    private static func renderedHeight(lines: Int) -> CGFloat {
        let text = (0..<lines).map { "line \($0)" }.joined(separator: "\n")
        let host = NSHostingView(rootView: TerminalScreenView(screen: TerminalScreen(text: text, cols: 40)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date())
        }
        return host.fittingSize.height
    }
}
#endif
