import Foundation

/// 3ペイン（左サイドバー・中央 detail・右インスペクター）の実効幅（task-1 契約面）。
struct PaneWidths: Equatable {
    var sidebar: CGFloat
    var inspector: CGFloat
}

/// ペイン幅クランプの純関数ポリシー（task-1 契約面）。
/// ウィンドウリサイズ・サイドバー開閉・ドラッグの各経路から DashboardView が呼ぶ、
/// 幅決定の単一の正本。契約は tasks/task-1.md と
/// AcceptancePaneWidthPolicyTests.swift（PM 著・不変）。
enum PaneWidthPolicy {
    static let sidebarMinWidth: CGFloat = 240
    static let inspectorMinWidth: CGFloat = 240
    static let detailMinWidth: CGFloat = 400

    /// ウィンドウ幅と表示状態から左右ペインの実効幅を返す。
    static func clamped(
        windowWidth: CGFloat,
        sidebarVisible: Bool,
        inspectorVisible: Bool,
        sidebarWidth: CGFloat,
        inspectorWidth: CGFloat
    ) -> PaneWidths {
        if !sidebarVisible && !inspectorVisible {
            return PaneWidths(sidebar: sidebarWidth, inspector: inspectorWidth)
        }

        let budget = windowWidth - detailMinWidth

        if sidebarVisible && inspectorVisible {
            var sidebar = sidebarWidth
            var inspector = inspectorWidth

            if sidebar + inspector > budget {
                inspector = max(inspectorMinWidth, min(inspector, budget - sidebar))
                if sidebar + inspector > budget {
                    sidebar = max(sidebarMinWidth, min(sidebar, budget - inspector))
                }
            }

            return PaneWidths(sidebar: sidebar, inspector: inspector)
        }

        if sidebarVisible {
            let sidebar = max(sidebarMinWidth, min(sidebarWidth, budget))
            return PaneWidths(sidebar: sidebar, inspector: inspectorWidth)
        }

        let inspector = max(inspectorMinWidth, min(inspectorWidth, budget))
        return PaneWidths(sidebar: sidebarWidth, inspector: inspector)
    }
}
