import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature

@Test func agentStartCardsLayoutPolicy_twoCards_requiredWidthIncludesSpacing() {
    let c = AgentStartCardsLayoutPolicy.cardMinOuterWidth
    let s = AgentStartCardsLayoutPolicy.interCardSpacing
    let p = AgentStartCardsLayoutPolicy.containerHorizontalPadding
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 2) == c * 2 + s + p * 2)
}

@Test func agentStartCardsLayoutPolicy_wideEnough_doesNotStack() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 2)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need + 100, cardCount: 2) == false)
}

@Test func agentStartCardsLayoutPolicy_zeroCardCount_requiredWidthIsPaddingOnly() {
    let p = AgentStartCardsLayoutPolicy.containerHorizontalPadding
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 0) == p * 2)
}

// MARK: - View wiring (ImageRenderer)

@MainActor
private func agentStartCardsLayoutDecision(
    paneWidth: CGFloat,
    cardCount: Int = 3
) -> Bool? {
    final class Box: @unchecked Sendable { var decision: Bool? }
    let box = Box()

    let kinds: [AgentKind] = [.claudeCode, .codex, .cursor]
    let cards = kinds.prefix(cardCount).map { AgentStartCard(kind: $0) }

    let view = AgentStartCardsView(
        cards: cards,
        isCreating: false,
        onSelect: { _, _ in },
        onLayoutDecision: { box.decision = $0 }
    )
    .frame(width: paneWidth, height: 800)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    _ = renderer.cgImage

    return box.decision
}

@Test @MainActor
func agentStartCards_narrowPane_stacksVertically() {
    let decision = agentStartCardsLayoutDecision(paneWidth: 400, cardCount: 3)
    #expect(decision == true)
}

@Test @MainActor
func agentStartCards_widePane_staysHorizontal() {
    let decision = agentStartCardsLayoutDecision(paneWidth: 700, cardCount: 3)
    #expect(decision == false)
}
