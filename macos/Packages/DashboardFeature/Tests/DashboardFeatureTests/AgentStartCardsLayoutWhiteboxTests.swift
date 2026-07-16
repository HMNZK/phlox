import Foundation
import Testing
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
