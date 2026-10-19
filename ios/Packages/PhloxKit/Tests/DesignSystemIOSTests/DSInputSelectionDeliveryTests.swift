import Testing
@testable import DesignSystemIOS

@MainActor
@Suite struct DSInputSelectionDeliveryTests {
    @MainActor private final class DraftState {
        var text = "入力前"
        var offsets: [Int] = []
    }

    @Test func defersNativeWritesAndKeepsOnlyLatestSelection() async {
        let delivery = DSInputSelectionDelivery()
        var offsets: [Int] = []
        let first = delivery.enqueue(isCurrent: { true }) { offsets.append(1) }
        let last = delivery.enqueue(isCurrent: { true }) { offsets.append(4) }
        #expect(offsets.isEmpty)
        await first.value
        await last.value
        #expect(offsets == [4])
    }

    @Test func externalCursorCancelsPendingNativeSelection() async {
        let delivery = DSInputSelectionDelivery()
        var offset = 0
        let pending = delivery.enqueue(isCurrent: { true }) { offset = 2 }
        delivery.invalidate()
        offset = 7
        await pending.value
        #expect(offset == 7)
    }

    @Test func changedTextRejectsOldIndicesAndKeepsNewSelection() async {
        let delivery = DSInputSelectionDelivery()
        let draft = DraftState()
        let capturedText = draft.text
        let stale = delivery.enqueue(isCurrent: { draft.text == capturedText }) { draft.offsets.append(3) }
        draft.text = "変換中の本文"
        await stale.value
        #expect(draft.offsets.isEmpty)
        let currentText = draft.text
        let current = delivery.enqueue(isCurrent: { draft.text == currentText }) { draft.offsets.append(6) }
        await current.value
        #expect(draft.offsets == [6])
    }
}
