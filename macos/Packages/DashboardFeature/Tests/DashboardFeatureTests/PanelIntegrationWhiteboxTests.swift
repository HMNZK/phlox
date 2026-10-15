import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DashboardFeature

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
