import Testing
@testable import SessionFeature

@MainActor
@Suite("Whitebox: composer の利用可能コマンド配線（task-5）")
struct ComposerWiringWhiteboxTests {

    @Test("利用可能コマンドの更新後は slash 候補がその一覧に一致する")
    func updatedAvailableSlashCommandsDriveSlashCandidates() async throws {
        let controller = ComposerSuggestionController.production(workingDirectory: "/tmp")

        controller.availableSlashCommands = ["deploy", "describe"]
        controller.update(text: "/dep", cursorUTF16: 4)
        try await waitForScan(controller)

        #expect(controller.candidates.map(\.title) == ["/deploy"])
    }

    private func waitForScan(_ controller: ComposerSuggestionController) async throws {
        for _ in 0..<100 where controller.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!controller.isScanning, "候補走査が 1 秒以内に完了すること")
    }
}
