import Testing
import Foundation
import AgentDomain
@testable import DesignSystem

@Suite @MainActor struct StatusLocalizedLabelTests {

    // MARK: - 日本語 (ja)

    @Test func runningJapanese() {
        #expect(StatusBadge.localizedLabel(for: .running, locale: Locale(identifier: "ja")) == "実行中")
    }

    @Test func startingJapanese() {
        #expect(StatusBadge.localizedLabel(for: .starting, locale: Locale(identifier: "ja")) == "起動中")
    }

    @Test func awaitingJapanese() {
        #expect(StatusBadge.localizedLabel(for: .awaitingApproval(prompt: "x"), locale: Locale(identifier: "ja")) == "承認待ち")
    }

    @Test func completedZeroJapanese() {
        #expect(StatusBadge.localizedLabel(for: .completed(exitCode: 0), locale: Locale(identifier: "ja")) == "完了 (0)")
    }

    @Test func errorJapanese() {
        #expect(StatusBadge.localizedLabel(for: .error(message: "boom"), locale: Locale(identifier: "ja")) == "エラー")
    }

    // MARK: - 英語 (en)

    @Test func runningEnglish() {
        #expect(StatusBadge.localizedLabel(for: .running, locale: Locale(identifier: "en")) == "running")
    }

    @Test func startingEnglish() {
        #expect(StatusBadge.localizedLabel(for: .starting, locale: Locale(identifier: "en")) == "starting")
    }

    @Test func awaitingEnglish() {
        #expect(StatusBadge.localizedLabel(for: .awaitingApproval(prompt: "x"), locale: Locale(identifier: "en")) == "awaiting")
    }

    @Test func completedZeroEnglish() {
        #expect(StatusBadge.localizedLabel(for: .completed(exitCode: 0), locale: Locale(identifier: "en")) == "done")
    }

    @Test func errorEnglish() {
        #expect(StatusBadge.localizedLabel(for: .error(message: "boom"), locale: Locale(identifier: "en")) == "error")
    }

    // MARK: - ja 以外は英語にフォールバック (fr)

    @Test func runningFrenchFallsBackToEnglish() {
        #expect(StatusBadge.localizedLabel(for: .running, locale: Locale(identifier: "fr")) == "running")
    }
}
