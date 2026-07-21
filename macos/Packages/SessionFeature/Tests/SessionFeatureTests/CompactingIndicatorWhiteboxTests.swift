import Testing
@testable import SessionFeature

@Suite("Compacting indicator 白箱（task-2）")
struct CompactingIndicatorWhiteboxTests {
    @Test func isCompactCommandはtrimと引数付きを認識する() {
        #expect(ChatSessionViewModel.isCompactCommand("/compact"))
        #expect(ChatSessionViewModel.isCompactCommand("  /compact  "))
        #expect(ChatSessionViewModel.isCompactCommand("/compact 直近の設計判断を残して"))
        #expect(!ChatSessionViewModel.isCompactCommand("compact について教えて"))
        #expect(!ChatSessionViewModel.isCompactCommand("/compaction"))
        #expect(!ChatSessionViewModel.isCompactCommand("/compactify"))
    }

    @Test func 圧縮中はthinkingインジケーターを抑止する() {
        #expect(CompactingIndicatorPresentation.shouldShowCompactingIndicator(isCompacting: true))
        #expect(!CompactingIndicatorPresentation.shouldShowCompactingIndicator(isCompacting: false))

        #expect(CompactingIndicatorPresentation.shouldShowThinkingIndicator(
            showsThinkingIndicator: true,
            showsProcessingIndicator: true,
            isCompacting: false
        ))
        #expect(!CompactingIndicatorPresentation.shouldShowThinkingIndicator(
            showsThinkingIndicator: true,
            showsProcessingIndicator: true,
            isCompacting: true
        ))
        #expect(!CompactingIndicatorPresentation.shouldShowThinkingIndicator(
            showsThinkingIndicator: false,
            showsProcessingIndicator: true,
            isCompacting: false
        ))
    }
}
