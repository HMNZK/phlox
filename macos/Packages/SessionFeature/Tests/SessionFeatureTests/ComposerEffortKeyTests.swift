import AppKit
import Testing
@testable import SessionFeature

// 入力欄の ⇧Tab は推論の深さを回す。Tab だけ・⌘⇧Tab は回さない。回せないとき（false）は入力欄の既定の動きに任せる。
@MainActor
@Suite struct ComposerEffortKeyTests {
    private func tab(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
        )!
    }

    @Test func shiftTabCyclesTheEffort() {
        let view = IMESafeTextView.SubmitAwareTextView()
        var cycles = 0
        view.onCycleEffort = { cycles += 1; return true }
        view.onTab = { false }

        view.keyDown(with: tab(.shift))
        #expect(cycles == 1)
        view.keyDown(with: tab([]))
        view.keyDown(with: tab([.shift, .command]))
        #expect(cycles == 1)
    }

    /// 変換中の ⇧Tab は IME に任せる。
    @Test func shiftTabWhileComposingIsLeftToTheInputMethod() {
        let view = IMESafeTextView.SubmitAwareTextView()
        var cycles = 0
        view.onCycleEffort = { cycles += 1; return true }
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())

        view.keyDown(with: tab(.shift))
        #expect(cycles == 0)
    }
}
