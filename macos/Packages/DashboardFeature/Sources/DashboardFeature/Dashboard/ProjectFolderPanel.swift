import AppKit
import DesignSystem

/// プロジェクトにするフォルダを選ぶパネル（⌘O・サイドバー・新規チャットのプロジェクトのチップで共用）。
@MainActor
enum ProjectFolderPanel {
    static func choose(locale: Locale) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalizedString.string("追加", locale: locale)
        panel.message = AppLocalizedString.string("プロジェクトとして使うフォルダを選択してください。", locale: locale)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
