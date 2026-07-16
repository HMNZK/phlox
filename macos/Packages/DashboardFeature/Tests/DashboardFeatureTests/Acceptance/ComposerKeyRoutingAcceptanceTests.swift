// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — composer キールーティングの純関数契約。
// 既存 SubmitAwareTextView.keyDown の挙動（Cmd+Return 送信・Shift+Return 改行・
// IME 変換中の Return は変換確定＝素通し・Esc は非変換時のみ escape）を意味を変えず凍結し、
// Ctrl+Z / Ctrl+Shift+Z の undo/redo を追加する。

import AppKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private let keyZ: UInt16 = 6
private let keyReturn: UInt16 = 36
private let keyKeypadEnter: UInt16 = 76
private let keyEscape: UInt16 = 53
private let keyA: UInt16 = 0

private func route(
    _ keyCode: UInt16,
    _ modifiers: NSEvent.ModifierFlags = [],
    composing: Bool = false
) -> ComposerKeyAction {
    ComposerKeyRouting.action(keyCode: keyCode, modifierFlags: modifiers, isComposing: composing)
}

@Test func composerKeyRouting_ctrlZ_isUndo_andCtrlShiftZ_isRedo() {
    #expect(route(keyZ, [.control]) == .undo)
    #expect(route(keyZ, [.control, .shift]) == .redo)
}

@Test func composerKeyRouting_cmdZ_usesComposerUndoRedo() {
    #expect(route(keyZ, [.command]) == .undo)
    #expect(route(keyZ, [.command, .shift]) == .redo)
}

@Test func composerKeyRouting_ctrlZ_whileComposing_passesToSystem() {
    #expect(route(keyZ, [.control], composing: true) == .passToSystem)
    #expect(route(keyZ, [.control, .shift], composing: true) == .passToSystem)
}

@Test func composerKeyRouting_plainReturn_submits_keypadEnterToo() {
    #expect(route(keyReturn) == .submit)
    #expect(route(keyKeypadEnter) == .submit)
}

@Test func composerKeyRouting_returnWhileComposing_passesToSystem() {
    #expect(route(keyReturn, composing: true) == .passToSystem)
    #expect(route(keyKeypadEnter, composing: true) == .passToSystem)
}

@Test func composerKeyRouting_cmdReturn_submits_evenWhileComposing() {
    #expect(route(keyReturn, [.command]) == .submit)
    #expect(route(keyReturn, [.command], composing: true) == .submit)
}

@Test func composerKeyRouting_shiftReturn_insertsNewline_evenWhileComposing() {
    #expect(route(keyReturn, [.shift]) == .insertNewline)
    #expect(route(keyReturn, [.shift], composing: true) == .insertNewline)
}

@Test func composerKeyRouting_modifiedReturn_otherModifiers_passToSystem() {
    #expect(route(keyReturn, [.control]) == .passToSystem)
    #expect(route(keyReturn, [.option]) == .passToSystem)
}

@Test func composerKeyRouting_escape_firesEscape_exceptWhileComposing() {
    #expect(route(keyEscape) == .escape)
    #expect(route(keyEscape, composing: true) == .passToSystem)
}

@Test func composerKeyRouting_ordinaryKey_passesToSystem() {
    #expect(route(keyA) == .passToSystem)
    #expect(route(keyA, [.control]) == .passToSystem)
}
