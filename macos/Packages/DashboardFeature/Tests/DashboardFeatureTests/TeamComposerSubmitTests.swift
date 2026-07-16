import AppKit
import Testing
@testable import DashboardFeature
import SessionFeature

private let keyReturn: UInt16 = 36
private let keyKeypadEnter: UInt16 = 76

@Test
func teamComposerKeyRouting_plainEnter_submits() {
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyReturn, modifierFlags: [], isComposing: false) == .submit
    )
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyKeypadEnter, modifierFlags: [], isComposing: false) == .submit
    )
}

@Test
func teamComposerKeyRouting_enterWhileComposing_passesToSystem() {
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyReturn, modifierFlags: [], isComposing: true) == .passToSystem
    )
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyKeypadEnter, modifierFlags: [], isComposing: true) == .passToSystem
    )
}

@Test
func teamComposerKeyRouting_shiftEnter_insertsNewline() {
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyReturn, modifierFlags: [.shift], isComposing: false) == .insertNewline
    )
    #expect(
        TeamComposerKeyRouting.action(keyCode: keyReturn, modifierFlags: [.shift], isComposing: true) == .insertNewline
    )
}

@Test
func teamComposerTextMetrics_resolvedHeight_clampsBetweenMinAndMax() {
    let minHeight = TeamComposerTextMetrics.minEditorHeight
    let maxHeight = TeamComposerTextMetrics.maxEditorHeight

    #expect(TeamComposerTextMetrics.resolvedHeight(usedTextHeight: 0) == minHeight)
    #expect(TeamComposerTextMetrics.resolvedHeight(usedTextHeight: 10_000) == maxHeight)
    #expect(minHeight < maxHeight)
}

@Test
func teamComposerTextMetrics_shouldWriteHeight_ignoresSubPointFiveChanges() {
    #expect(TeamComposerTextMetrics.shouldWriteHeight(current: 40, next: 40.4) == false)
    #expect(TeamComposerTextMetrics.shouldWriteHeight(current: 40, next: 40.6) == true)
}
