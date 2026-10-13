import SwiftUI
import AgentDomain
import DesignSystem

/// 右端のインスペクタ。ファイルツリーだけを出す（ADR 0192）。
struct InspectorView: View {
    @Bindable var router: AppRouter
    let project: Project?
    @Binding var fileTreeModels: [String: FileTreeModel]
    let files: FileTabDocuments
    var isOverlay = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        FileTreeInspectorView(router: router, project: project, models: $fileTreeModels, files: files, isOverlay: isOverlay)
            .background(isOverlay ? DSColor.popoverBackground : DSColor.surface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("インスペクタ"))
    }
}
