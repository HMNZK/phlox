import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

@Suite("task-2: composer 画像番号付け 白箱テスト")
struct ComposerImageNumberingWhiteboxTests {

    private func image(_ byte: UInt8) -> Data {
        Data([byte])
    }

    @Test @MainActor
    func removingAttachmentPlaceholder_collapsesAdjacentSpace() {
        let text = "hello [Image #2] world"
        let result = ComposerImagePlaceholder.removing(number: 2, from: text)
        #expect(result == "hello world")
    }

    @Test @MainActor
    func plusButtonPath_insertsPlaceholderAtDraftEnd() {
        var draft = "見て"
        let applied = ComposerImagePlaceholder.inserting(
            number: 1,
            into: draft,
            cursorUTF16: draft.utf16.count
        )
        draft = applied.text
        #expect(draft == "見て [Image #1] ")
    }

    @Test @MainActor
    func rejectedAddImage_doesNotAdvanceNumbering() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")
        let tooLarge = Data(count: ComposerAttachmentStore.maxBytesPerImage + 1)

        let rejected = store.addImage(data: tooLarge, mediaType: "image/png")
        let next = store.addImage(data: image(2), mediaType: "image/png")

        #expect(rejected == nil)
        #expect(next?.number == 2)
        #expect(store.attachments.map(\.number) == [1, 2])
    }

    @Test @MainActor
    func chipBadge_reflectsAttachmentNumber() {
        let attachment = ComposerAttachment(number: 5, data: image(1), mediaType: "image/png", filename: "a.png")
        #expect(ComposerAttachmentChipPresentation.badge(for: attachment) == "#5")
        #expect(ComposerAttachmentChipPresentation.title(for: attachment) == "a.png")
    }
}
