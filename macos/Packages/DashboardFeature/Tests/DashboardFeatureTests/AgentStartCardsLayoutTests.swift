import AppKit
import Foundation
import SwiftUI
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature

// エージェント選択カード列の並び方向ポリシー: 必要幅 = n×カード外形幅 + (n-1)×間隔 + 左右 padding。
// 丁度収まる幅は横並びのまま、1pt でも足りなければ縦積み。カード 1 枚以下は縦積みしない。

// 必要幅は枚数に対して線形
@Test func agentStartCardsLayout_requiredWidth_isLinearInCardCount() {
    let c = AgentStartCardsLayoutPolicy.cardMinOuterWidth
    let s = AgentStartCardsLayoutPolicy.interCardSpacing
    let p = AgentStartCardsLayoutPolicy.containerHorizontalPadding
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 1) == c + p * 2)
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3) == c * 3 + s * 2 + p * 2)
}

@Test func agentStartCardsLayoutPolicy_zeroCardCount_requiredWidthIsPaddingOnly() {
    let p = AgentStartCardsLayoutPolicy.containerHorizontalPadding
    #expect(AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 0) == p * 2)
}

// 丁度収まる幅では横並びのまま
@Test func agentStartCardsLayout_exactFit_staysHorizontal() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need, cardCount: 3) == false)
}

@Test func agentStartCardsLayoutPolicy_wideEnough_doesNotStack() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 2)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need + 100, cardCount: 2) == false)
}

// 1pt でも足りなければ縦積み
@Test func agentStartCardsLayout_oneShort_stacksVertically() {
    let need = AgentStartCardsLayoutPolicy.requiredHorizontalWidth(cardCount: 3)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: need - 1, cardCount: 3) == true)
}

// カード1枚以下は縦積みしない（横=縦で同義のため常に横並び扱い）
@Test func agentStartCardsLayout_singleOrNoCard_neverStacks() {
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: 0, cardCount: 1) == false)
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: -10, cardCount: 0) == false)
}

// 幅ゼロで複数枚なら縦積み
@Test func agentStartCardsLayout_zeroWidth_stacks() {
    #expect(AgentStartCardsLayoutPolicy.shouldStackVertically(availableWidth: 0, cardCount: 2) == true)
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
