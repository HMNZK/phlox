// task-7 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-7.md — チャット入力欄のスラッシュコマンド・@参照サジェスト。

import AppKit
import Foundation
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - トリガー検出（純関数）

@Test func composerSuggestion_trigger_slashFiresAtAnyTokenStart() {
    // 先頭の "/"（不変）
    #expect(SuggestionTrigger.query(text: "/co", cursorUTF16: 3)
        == SuggestionQuery(kind: .slashCommand, tokenRange: 0..<3, searchTerm: "co"))
    // 文中でも空白区切りトークン先頭の "/" で発火する
    #expect(SuggestionTrigger.query(text: "hello /co", cursorUTF16: 9)
        == SuggestionQuery(kind: .slashCommand, tokenRange: 6..<9, searchTerm: "co"))
    // トークン途中の "/"（パス等）は発火しない
    #expect(SuggestionTrigger.query(text: "src/main", cursorUTF16: 8) == nil)
}

@Test func composerSuggestion_trigger_slashAloneShowsAllCommands() {
    #expect(SuggestionTrigger.query(text: "/", cursorUTF16: 1)
        == SuggestionQuery(kind: .slashCommand, tokenRange: 0..<1, searchTerm: ""))
}

@Test func composerSuggestion_trigger_atTokenStart() {
    // カーソル直前の空白区切りトークンが "@" で始まる
    let query = SuggestionTrigger.query(text: "see @Pack", cursorUTF16: 9)
    #expect(query == SuggestionQuery(kind: .fileReference, tokenRange: 4..<9, searchTerm: "Pack"))
}

@Test func composerSuggestion_trigger_atInsideTokenDoesNotFire() {
    // メールアドレスのような途中 "@" は発火しない
    #expect(SuggestionTrigger.query(text: "mail a@b", cursorUTF16: 8) == nil)
}

@Test func composerSuggestion_trigger_noTriggerReturnsNil() {
    #expect(SuggestionTrigger.query(text: "plain text", cursorUTF16: 10) == nil)
    #expect(SuggestionTrigger.query(text: "", cursorUTF16: 0) == nil)
}

// MARK: - コントローラ（fake 供給源を注入）

@MainActor
private func makeController(
    slash: [SuggestionCandidate] = [
        SuggestionCandidate(title: "/compact", insertionText: "/compact", kind: .slashCommand),
        SuggestionCandidate(title: "/clear", insertionText: "/clear", kind: .slashCommand),
        SuggestionCandidate(title: "/model", insertionText: "/model", kind: .slashCommand),
    ],
    files: @escaping (String) -> [SuggestionCandidate] = { term in
        term.isEmpty ? [] : [SuggestionCandidate(title: "Packages/Foo.swift", insertionText: "@Packages/Foo.swift", kind: .fileReference)]
    }
) -> ComposerSuggestionController {
    ComposerSuggestionController(slashProvider: { slash }, fileProvider: files)
}

@Test @MainActor
func composerSuggestion_controller_filtersSlashByPrefixAndPresents() {
    let controller = makeController()
    controller.update(text: "/c", cursorUTF16: 2)
    #expect(controller.isPresented)
    #expect(controller.candidates.map(\.insertionText) == ["/compact", "/clear"])
    #expect(controller.selectedIndex == 0)
}

@Test @MainActor
func composerSuggestion_controller_slashFiresMidText() {
    // 本文の後ろの "/" でも候補が表示される（ユーザー要件のエンドツーエンド経路）
    let controller = makeController()
    controller.update(text: "本文 /c", cursorUTF16: 5)
    #expect(controller.isPresented)
    #expect(controller.candidates.map(\.insertionText) == ["/compact", "/clear"])
}

@Test @MainActor
func composerSuggestion_controller_keepsAllCandidatesWithoutCap() {
    // 契約変更（ユーザー要件）: 8件上限を撤去し全件保持（超過分はポップアップの ScrollView で到達）。
    let many = (0..<20).map {
        SuggestionCandidate(title: "/cmd\($0)", insertionText: "/cmd\($0)", kind: .slashCommand)
    }
    let controller = makeController(slash: many)
    controller.update(text: "/cmd", cursorUTF16: 4)
    #expect(controller.candidates.count == 20)
}

@Test @MainActor
func composerSuggestion_controller_moveSelectionClampsAtEnds() {
    let controller = makeController()
    controller.update(text: "/c", cursorUTF16: 2)
    controller.moveSelection(-1)
    #expect(controller.selectedIndex == 0)
    controller.moveSelection(1)
    #expect(controller.selectedIndex == 1)
    controller.moveSelection(1)
    #expect(controller.selectedIndex == 1)
}

@Test @MainActor
func composerSuggestion_controller_acceptReplacesTokenAndAppendsSpace() {
    let controller = makeController()
    controller.update(text: "/c", cursorUTF16: 2)
    controller.moveSelection(1)
    let replacement = controller.acceptSelected()
    #expect(replacement == SuggestionReplacement(range: 0..<2, text: "/clear "))
    #expect(!controller.isPresented)
}

@Test @MainActor
func composerSuggestion_controller_fileQueryUsesProviderAndDismisses() {
    let controller = makeController()
    controller.update(text: "see @Pa", cursorUTF16: 7)
    #expect(controller.isPresented)
    #expect(controller.candidates.first?.insertionText == "@Packages/Foo.swift")
    controller.dismiss()
    #expect(!controller.isPresented)
    #expect(controller.acceptSelected() == nil)
}

@Test @MainActor
func composerSuggestion_controller_noTriggerClearsCandidates() {
    let controller = makeController()
    controller.update(text: "/c", cursorUTF16: 2)
    #expect(controller.isPresented)
    controller.update(text: "plain", cursorUTF16: 5)
    #expect(!controller.isPresented)
}

// MARK: - キールーティング（サジェスト表示中）

private func routeS(
    _ keyCode: UInt16,
    _ modifiers: NSEvent.ModifierFlags = [],
    composing: Bool = false,
    visible: Bool = true
) -> ComposerKeyAction {
    ComposerKeyRouting.action(
        keyCode: keyCode,
        modifierFlags: modifiers,
        isComposing: composing,
        suggestionsVisible: visible
    )
}

@Test func composerSuggestion_keyRouting_arrowsNavigateWhileVisible() {
    #expect(routeS(125) == .moveSuggestionDown)
    #expect(routeS(126) == .moveSuggestionUp)
}

@Test func composerSuggestion_keyRouting_tabAndReturnAccept_escDismisses() {
    #expect(routeS(48) == .acceptSuggestion)
    #expect(routeS(36) == .acceptSuggestion)
    #expect(routeS(53) == .dismissSuggestions)
}

@Test func composerSuggestion_keyRouting_imeComposingTakesPriority() {
    #expect(routeS(36, composing: true) == .passToSystem)
    #expect(routeS(125, composing: true) == .passToSystem)
    #expect(routeS(53, composing: true) == .passToSystem)
}

@Test func composerSuggestion_keyRouting_nonNavigationKeysKeepNormalRouting() {
    #expect(routeS(6, [.control]) == .undo)
    #expect(routeS(36, [.shift]) == .insertNewline)
}

@Test func composerSuggestion_keyRouting_hiddenBehavesAsBefore() {
    #expect(routeS(125, visible: false) == .passToSystem)
    #expect(routeS(36, visible: false) == .submit)
    #expect(routeS(53, visible: false) == .escape)
}
