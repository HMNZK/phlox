// composer のコンテキスト使用量ゲージ。fraction の nil/クランプ規則、ツールチップ文言、警告レベルの境界。

import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

// MARK: - ComposerContextGauge.fraction

@Test func contextGauge_nilUsage_returnsNil() {
    #expect(ComposerContextGauge.fraction(for: nil) == nil)
}

@Test func contextGauge_explicitUsedAndWindow_returnsRatio() {
    let usage = TurnUsage(contextUsedTokens: 50_000, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == 0.25)
}

@Test func contextGauge_derivesUsedFromTokenFieldsWhenContextUsedNil() {
    // Claude 形: contextUsedTokens は nil、input + cacheRead + cacheCreation から導出する。
    let usage = TurnUsage(
        inputTokens: 10_000,
        cacheReadTokens: 80_000,
        cacheCreationTokens: 10_000,
        contextWindowTokens: 200_000
    )
    #expect(ComposerContextGauge.fraction(for: usage) == 0.5)
}

@Test func contextGauge_outputTokensAreNotCountedAsContextUse() {
    let usage = TurnUsage(
        inputTokens: 100_000,
        outputTokens: 50_000,
        contextWindowTokens: 200_000
    )
    #expect(ComposerContextGauge.fraction(for: usage) == 0.5)
}

@Test func contextGauge_missingWindow_returnsNil() {
    let usage = TurnUsage(inputTokens: 10_000)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_zeroWindow_returnsNil() {
    let usage = TurnUsage(contextUsedTokens: 10, contextWindowTokens: 0)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_missingUsed_returnsNil() {
    let usage = TurnUsage(costUSD: 1.0, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == nil)
}

@Test func contextGauge_overflow_isClampedToOne() {
    let usage = TurnUsage(contextUsedTokens: 300_000, contextWindowTokens: 200_000)
    #expect(ComposerContextGauge.fraction(for: usage) == 1.0)
}

// MARK: - ツールチップ文言・警告レベル

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
