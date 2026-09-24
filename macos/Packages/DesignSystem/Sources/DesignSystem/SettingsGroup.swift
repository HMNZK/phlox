/// 設定画面の目的別グループ。タブの id・表示名・シンボルと所属 Section ID の静的分類。
/// 保存キーではなく表示分類であり、I/O や設定値を持たない。
public struct SettingsGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sectionIDs: [String]

    /// 10 Settings の 6 タブ。「詳細」を解体して使用量を独立させ、通知を「一般」から分けた。
    public static let all: [SettingsGroup] = [
        SettingsGroup(id: "general", title: "一般", systemImage: "gearshape", sectionIDs: ["language", "updates", "about"]),
        SettingsGroup(id: "appearance", title: "外観", systemImage: "paintpalette", sectionIDs: ["theme", "app-icon", "text-size"]),
        SettingsGroup(id: "notifications", title: "通知", systemImage: "bell.badge", sectionIDs: ["notifications"]),
        SettingsGroup(id: "agents", title: "エージェント", systemImage: "wrench.and.screwdriver", sectionIDs: ["permissions", "agent-management"]),
        SettingsGroup(id: "usage", title: "使用量", systemImage: "gauge.with.dots.needle.33percent", sectionIDs: ["usage"]),
        SettingsGroup(id: "mobile", title: "モバイル連携", systemImage: "iphone", sectionIDs: ["mobile-connection", "paired-devices"]),
    ]
}
