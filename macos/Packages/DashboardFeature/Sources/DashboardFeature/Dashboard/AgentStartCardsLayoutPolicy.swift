import Foundation
import DesignSystem

/// 空状態エージェント選択カード列の並び方向（横並び/縦積み）を決める純関数ポリシー
/// （task-2 契約面）。契約は tasks/task-2.md と
/// AcceptanceAgentStartCardsLayoutTests.swift（PM 著・不変）。
enum AgentStartCardsLayoutPolicy {
    /// カード1枚の外形最小幅 = ボタン minWidth 148 + 内側 padding(DSSpacing.m) 左右。
    /// AgentStartCardButton の実装値と一致させる。
    static let cardMinOuterWidth: CGFloat = 148 + DSSpacing.m * 2
    /// カード間の間隔（AgentStartCardsView の HStack spacing と一致させる）。
    static let interCardSpacing: CGFloat = DSSpacing.m
    /// コンテナ外周の横 padding（AgentStartCardsView の .padding と一致させる）。
    static let containerHorizontalPadding: CGFloat = DSSpacing.l

    /// n 枚を横並びで崩れず表示するのに必要な最小幅。
    static func requiredHorizontalWidth(cardCount: Int) -> CGFloat {
        let cardWidth = CGFloat(cardCount) * cardMinOuterWidth
        let spacingWidth = CGFloat(max(0, cardCount - 1)) * interCardSpacing
        return cardWidth + spacingWidth + containerHorizontalPadding * 2
    }

    /// 利用可能幅が横並びに足りなければ true（縦積みへ切替）。
    static func shouldStackVertically(availableWidth: CGFloat, cardCount: Int) -> Bool {
        guard cardCount >= 2 else { return false }
        return availableWidth < requiredHorizontalWidth(cardCount: cardCount)
    }
}
