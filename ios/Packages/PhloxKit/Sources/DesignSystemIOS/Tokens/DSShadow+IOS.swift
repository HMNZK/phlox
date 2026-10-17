import SwiftUI
import DesignSystem

public extension DSShadow {
  /// ダイアログ elevation。Camp: `0 30px 60px -15px rgba(0,0,0,.7)`。
  static let dialog = DSShadow(color: Color.black.opacity(0.7), radius: 60, x: 0, y: 30)
}
