// task-1 契約の PM スタブ。API 表面は受け入れテスト
// ChatFixTask1SidebarGridAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-1.md（viewMode 切替時のサイドバー表示の純関数ポリシー）。

/// viewMode 切替後のサイドバー表示を決める純関数ポリシー。
enum SidebarVisibilityPolicy {
    static func visibility(
        afterSwitchingTo newMode: ViewMode,
        currentVisible: Bool,
        hasGridFilter: Bool
    ) -> Bool {
        switch newMode {
        case .grid:
            currentVisible
        case .single, .team:
            true
        }
    }
}
