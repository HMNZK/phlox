import Testing
@testable import SessionFeature

@Suite struct SelectablePopoverTests {
    @Test func keyboardSelectionStartsAtCurrentOptionAndMovesWithArrowKeys() {
        var navigation = SelectablePopoverNavigation()
        let options = ["claude", "codex", "cursor"]

        navigation.reset(availableIDs: options, selectedID: "codex")
        #expect(navigation.highlightedID == "codex")
        #expect(navigation.selectionID(among: options) == "codex")
        navigation.move(by: 1, among: options)
        #expect(navigation.highlightedID == "cursor")
        #expect(navigation.selectionID(among: options) == "cursor")
        navigation.move(by: -1, among: options)
        #expect(navigation.highlightedID == "codex")
        navigation.move(by: -1, among: options)
        #expect(navigation.highlightedID == "claude")
    }

    @Test func keyboardSelectionSkipsDisabledRowsAndHandlesEmptyLists() {
        var navigation = SelectablePopoverNavigation()
        navigation.reset(availableIDs: ["first", "last"], selectedID: "disabled")
        #expect(navigation.highlightedID == "first")
        navigation.move(by: -1, among: [])
        #expect(navigation.highlightedID == nil)
    }

    @Test func pointerAndKeyboardUseOneActiveHighlight() {
        var navigation = SelectablePopoverNavigation()
        let options = ["selected", "pointer", "keyboard"]

        navigation.reset(availableIDs: options, selectedID: "selected")
        #expect(navigation.highlightSource == .keyboard)
        #expect(navigation.highlightedID == "selected")

        navigation.movePointer(to: "pointer", among: options)
        #expect(navigation.highlightSource == .pointer)
        #expect(navigation.highlightedID == "pointer")

        navigation.move(by: 1, among: options)
        #expect(navigation.highlightSource == .keyboard)
        #expect(navigation.highlightedID == "keyboard")
        navigation.clearPointerHighlight(for: "pointer")
        #expect(navigation.highlightedID == "keyboard")
    }
}
