import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DashboardFeature

// レビュー MUST-1 の白箱テスト: 変更タブの左右分割は内在最小幅
// (`EditorPanelLayout.splitMinimumWidth` ≈ 541pt) を持つ。分割なしのタブ幅では `.split` を表示し、
// 左右分割の片側の最小幅 320pt（02 C）では `.stacked`（縦積み）へ切り替える。
@Suite("Editor panel layout white-box tests")
struct EditorPanelLayoutWhiteboxTests {
    @Test("分割なしのタブ幅では左右分割、分割表示の片側の最小幅では縦積みになる")
    func editorStacksInsideSplitPane() {
        #expect(EditorPanelLayout.mode(forWidth: 960) == .split)
        #expect(EditorPanelLayout.mode(forWidth: 320) == .stacked)
    }

    @Test("左右分割の内在最小幅ちょうどでは分割、1pt 下回ると縦積み")
    func editorSwitchesAtSplitMinimumWidthBoundary() {
        #expect(EditorPanelLayout.mode(forWidth: EditorPanelLayout.splitMinimumWidth) == .split)
        #expect(EditorPanelLayout.mode(forWidth: EditorPanelLayout.splitMinimumWidth - 1) == .stacked)
    }

    @Test("十分に広い幅では左右分割になる")
    func editorSplitsWhenWide() {
        #expect(EditorPanelLayout.mode(forWidth: 700) == .split)
        #expect(EditorPanelLayout.splitMinimumWidth <= 700)
    }
}

@Suite("Editor panel icon white-box tests")
struct EditorPanelIconWhiteboxTests {
    @Test("すべての変更種別とバイナリ状態で有効なSF Symbolを返す")
    func changeIconsExistInAppKit() {
        let kinds: [WorkingTreeChange.Kind] = [.modified, .added, .deleted, .untracked, .renamed]
        for kind in kinds {
            for isBinary in [false, true] {
                let change = WorkingTreeChange(path: "fixture", kind: kind, isBinary: isBinary)
                let name = editorChangeIcon(for: change)
                #expect(
                    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    "SF Symbol が存在しません: \(name)"
                )
            }
        }
    }
}
