import CoreGraphics
import DesignSystem

/// iOS カンプ由来の角丸トークン。design.md §2.3 の実値を共有 `DSRadius` に追加する。
public extension DSRadius {
  /// カード角丸（14px）。
  static let card: CGFloat = 14
  /// 削除確認などダイアログ角丸（22px）。
  static let dialog: CGFloat = 22
  /// アクションシート角丸（16px）。
  static let actionSheet: CGFloat = 16
}
