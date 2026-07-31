import Foundation

/// trailing ドロワーの幅決定を SwiftUI から分離する純粋なレイアウト規則。
/// ドラッグ中はこの値をプレビューにだけ使い、確定時だけ永続化された幅を更新する。
public enum PanelDrawerLayout {
    public static let defaultsKey = "phlox.panelDrawer.width"
    public static let preferredWidth: CGFloat = 420
    public static let minimumWidth: CGFloat = 280

    public static func clamped(width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let available = max(0, availableWidth)
        guard available >= minimumWidth else { return available }
        return min(available, max(minimumWidth, width))
    }

    /// trailing 境界は左へ動かすほどドロワーが広くなる。
    public static func proposedWidth(
        startWidth: CGFloat,
        translation: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        clamped(width: startWidth - translation, availableWidth: availableWidth)
    }
}
