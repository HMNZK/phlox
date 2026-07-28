import Testing
@testable import SessionFeature

@MainActor
@Suite("Whitebox: composer の利用可能コマンド状態（task-3）")
struct ComposerAvailableCommandsWhiteboxTests {

    @Test("nil は静的フォールバック、空配列は候補なし")
    func nilAndEmptyAvailableCommandsAreDistinct() async throws {
        let controller = ComposerSuggestionController.production(workingDirectory: "/tmp")

        controller.update(text: "/clear", cursorUTF16: 6)
        try await waitForScan(controller)
        #expect(controller.candidates.map(\.title).contains("/clear"))

        controller.availableSlashCommands = []
        controller.update(text: "/clear", cursorUTF16: 6)
        try await waitForScan(controller)
        #expect(controller.candidates.isEmpty)
    }

    private func waitForScan(_ controller: ComposerSuggestionController) async throws {
        for _ in 0..<100 where controller.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!controller.isScanning, "候補走査が 1 秒以内に完了すること")
    }
}
