import Foundation
import DesignSystem

/// 3 ペイン（左サイドバー・中央・右インスペクタ）の配置。
struct PaneLayout: Equatable {
    var sidebar: CGFloat
    var inspector: CGFloat
    /// サイドバーを横に並べて出すか。ユーザーが開いていても、幅が足りなければ自動で隠す。
    var showsSidebar: Bool
    /// インスペクタを中央の上に重ねて出すか（横に並べる幅が無いとき）。
    var inspectorIsOverlay: Bool
}

/// ペイン幅と縮退の純関数ポリシー。ウィンドウリサイズ・開閉・ドラッグの各経路から DashboardView が呼ぶ。
/// 中央が 480pt を割るときは、まずインスペクタを重ね表示にし、それでも足りなければサイドバーを自動で隠す（01 D）。
enum PaneWidthPolicy {
    static let sidebarRange = DSLayout.sidebarWidth
    static let inspectorRange = DSLayout.inspectorWidth
    static let centerMinWidth: CGFloat = 480
    /// 境界線 1 本の幅。
    static let separatorWidth: CGFloat = 1

    static func resolve(
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        inspectorVisible: Bool,
        sidebarWidth: CGFloat,
        inspectorWidth: CGFloat
    ) -> PaneLayout {
        let sidebar = sidebarRange.clamped(sidebarWidth)
        let inspector = inspectorRange.clamped(inspectorWidth)
        let sidebarSpan = sidebarVisible ? sidebar + separatorWidth : 0
        let inspectorSpan = inspectorVisible ? inspector + separatorWidth : 0

        let fitsDocked = windowWidth - sidebarSpan - inspectorSpan >= centerMinWidth
        let inspectorIsOverlay = inspectorVisible && !fitsDocked
        let showsSidebar = sidebarVisible && windowWidth - sidebarSpan >= centerMinWidth
        return PaneLayout(
            sidebar: sidebar,
            inspector: inspector,
            showsSidebar: showsSidebar,
            inspectorIsOverlay: inspectorIsOverlay
        )
    }

    /// 境界ドラッグ中のサイドバー幅。範囲内に収め、中央 480pt を割り込まない。
    static func draggedSidebarWidth(start: CGFloat, translation: CGFloat, windowWidth: CGFloat, inspectorSpan: CGFloat) -> CGFloat {
        let limit = windowWidth - inspectorSpan - centerMinWidth - separatorWidth
        return sidebarRange.clamped(min(start + translation, max(sidebarRange.min, limit)))
    }

    /// 境界ドラッグ中のインスペクタ幅（右端から左へ引くと広がる）。
    static func draggedInspectorWidth(start: CGFloat, translation: CGFloat, windowWidth: CGFloat, sidebarSpan: CGFloat) -> CGFloat {
        let limit = windowWidth - sidebarSpan - centerMinWidth - separatorWidth
        return inspectorRange.clamped(min(start - translation, max(inspectorRange.min, limit)))
    }
}
