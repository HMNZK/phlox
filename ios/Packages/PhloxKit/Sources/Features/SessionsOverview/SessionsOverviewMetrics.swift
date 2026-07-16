import SwiftUI
import DesignSystemIOS

/// SessionsOverview のレイアウト寸法（テスト可能な決定点）。
enum SessionsOverviewMetrics {
  /// グリッドの最小カード幅（2 列想定の adaptive）。
  static let gridMinimumCardWidth: CGFloat = 160
  /// グリッド列間隔。
  static let gridColumnSpacing = DSSpacing.m
  /// グリッド行間隔。
  static let gridRowSpacing = DSSpacing.m
  /// シングル集中カードの内側余白。
  static let singleCardPadding = DSSpacing.l
  /// カード角丸（カンプ準拠）。
  static let cardCornerRadius = DSRadius.card
}
