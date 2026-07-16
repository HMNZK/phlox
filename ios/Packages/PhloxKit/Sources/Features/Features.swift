// Features モジュール（E1-1 骨組み）。
// 画面別 ViewModel + View（Connection / SessionList / Detail / Spawn ...）は E4-x で実装する。
// DesignSystemIOS への依存は E2-2 以降で wire する。
import SwiftUI
import PhloxCore
// E2-1: 共有コア DesignSystem（iOS 多プラットフォーム化済み）の import 可否を実証する。
import DesignSystem

public enum Features {
    /// E2-1 の iOS コンパイル実証用。共有 DesignSystem のコアトークンが iOS から参照できることを示す。
    /// （UI 実装は E2-2 以降。ここではコンパイル時に型解決できることだけを保証する。）
    static let designSystemSmokeCheck: (Color, CGFloat) = (
        DSColor.accent,
        DSSpacing.l
    )
}
