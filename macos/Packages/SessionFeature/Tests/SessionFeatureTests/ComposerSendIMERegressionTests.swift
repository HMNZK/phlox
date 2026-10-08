import AppKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("送信後の日本語入力通知")
@MainActor
struct ComposerSendIMERegressionTests {
    @Test("送信後の遅延した確定通知は消した下書きを復活させない")
    func delayedCommitDoesNotRestoreSentText() throws {
        let harness = Harness()
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        harness.view.keyDown(with: event)
        #expect(harness.text.isEmpty)
        harness.view.unmarkText()
        harness.view.unmarkText()
        #expect(harness.text.isEmpty)
        harness.view.syncStringFromBinding(harness.text)
        #expect(harness.view.string.isEmpty)
    }

    @Test("変換中から確定への遷移は確定した本文を反映する")
    func realCommitUpdatesDraft() {
        let harness = Harness()
        harness.coordinator.setComposing(true, currentText: "へんかん")
        #expect(harness.composing)
        harness.coordinator.setComposing(false, currentText: "変換")
        #expect(harness.text == "変換")
        #expect(!harness.composing)
    }

    @Test("変換していない通常編集は本文へ反映する")
    func ordinaryEditsUpdateDraft() {
        let harness = Harness()
        harness.view.string = "次の下書き"
        harness.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: harness.view))
        #expect(harness.text == "次の下書き")
    }

    @MainActor
    private final class Harness {
        var text = "送信済みの文章"
        var composing = false
        let view = IMESafeTextView.SubmitAwareTextView()
        var coordinator: IMESafeTextView.Coordinator!

        init() {
            let parent = IMESafeTextView(
                text: Binding(get: { [weak self] in self?.text ?? "" }, set: { [weak self] in self?.text = $0 }),
                isComposing: Binding(get: { [weak self] in self?.composing ?? false }, set: { [weak self] in self?.composing = $0 }),
                measuredHeight: .constant(40), minHeight: 40, maxHeight: 160,
                suggestionController: nil, onSubmit: { [weak self] in self?.text = "" }
            )
            coordinator = parent.makeCoordinator()
            view.string = text
            view.onSubmit = parent.onSubmit
            view.onComposingChanged = { [weak self] composing, text in self?.coordinator.setComposing(composing, currentText: text) }
        }
    }
}
