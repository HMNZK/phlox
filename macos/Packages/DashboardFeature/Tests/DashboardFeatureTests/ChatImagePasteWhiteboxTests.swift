import AppKit
import Testing
@testable import SessionFeature

private let keyV: UInt16 = 9

@Test
func chatImagePaste_cmdV_routesToPasteOutsideIME() {
    #expect(ComposerKeyRouting.action(
        keyCode: keyV,
        modifierFlags: [.command],
        isComposing: false
    ) == .paste)
}

@Test
func chatImagePaste_cmdV_doesNotBypassIMEComposition() {
    #expect(ComposerKeyRouting.action(
        keyCode: keyV,
        modifierFlags: [.command],
        isComposing: true
    ) == .passToSystem)
}

@Test
func chatImagePaste_modifiedV_staysWithSystem() {
    #expect(ComposerKeyRouting.action(
        keyCode: keyV,
        modifierFlags: [.command, .option],
        isComposing: false
    ) == .passToSystem)
}
