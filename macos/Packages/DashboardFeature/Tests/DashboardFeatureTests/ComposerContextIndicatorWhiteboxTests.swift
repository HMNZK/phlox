import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Test func composerContextGauge_helpText_formatsPercentAndCounts() {
    let usage = TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.helpText(for: usage) == "使用 25% (50000/200000)")
}

@Test func composerContextGauge_helpText_derivesUsedFromTokenFields() {
    let usage = TurnUsage(
        inputTokens: 10_000,
        cacheReadTokens: 80_000,
        cacheCreationTokens: 10_000,
        contextWindowTokens: 200_000
    )
    #expect(ComposerContextGauge.helpText(for: usage) == "使用 50% (100000/200000)")
}

@Test func composerContextGauge_helpText_nilWhenFractionUnavailable() {
    #expect(ComposerContextGauge.helpText(for: nil) == nil)
    #expect(ComposerContextGauge.helpText(for: TurnUsage(inputTokens: 1)) == nil)
}

@Test func composerContextGauge_warningLevel_boundaryAtEightyPercent() {
    #expect(ComposerContextGauge.isWarningLevel(fraction: 0.79) == false)
    #expect(ComposerContextGauge.isWarningLevel(fraction: 0.8) == true)
    #expect(ComposerContextGauge.isWarningLevel(fraction: 1.0) == true)
}
