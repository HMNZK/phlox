/// 設定画面の目的別グループ。タブの id・表示名・シンボルと所属 Section ID の静的分類。
/// 保存キーではなく表示分類であり、I/O や設定値を持たない。
public struct SettingsGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sectionIDs: [String]

    public static let all: [SettingsGroup] = [
        SettingsGroup(id: "general", title: "一般", systemImage: "gearshape", sectionIDs: ["language", "sessions", "notifications", "updates"]),
        SettingsGroup(id: "appearance", title: "外観", systemImage: "paintpalette", sectionIDs: ["theme", "app-icon"]),
        SettingsGroup(id: "agents", title: "エージェント", systemImage: "wrench.and.screwdriver", sectionIDs: ["permissions", "agent-management"]),
        SettingsGroup(id: "connection", title: "接続", systemImage: "network", sectionIDs: ["mobile-connection", "paired-devices"]),
        SettingsGroup(id: "advanced", title: "詳細", systemImage: "slider.horizontal.3", sectionIDs: ["usage", "privacy", "about"]),
    ]
}
