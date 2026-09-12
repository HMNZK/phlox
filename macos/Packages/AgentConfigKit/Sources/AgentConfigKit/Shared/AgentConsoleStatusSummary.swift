/// エージェント管理の状態ペイン先頭に出す、CLI 検出と設定ファイル有無の要約。
/// CLI パスが見つかったことと認証・通信の成功は別であり、設定ファイル未作成は異常ではない。
public struct AgentConsoleStatusSummary: Equatable, Sendable {
    public let availabilityText: String
    public let availabilityDetail: String
    public let configurationText: String
    public let configurationDetail: String?
    public let cliDetailsTitle: String

    public static func make(isAvailable: Bool, configFileExists: Bool) -> AgentConsoleStatusSummary {
        AgentConsoleStatusSummary(
            availabilityText: isAvailable ? "CLI を検出済み" : "CLI を検出できていません",
            availabilityDetail: isAvailable
                ? "認証・通信の状態は未確認です"
                : "インストール先と PATH を確認してください",
            configurationText: configFileExists ? "設定ファイルあり" : "設定ファイル未作成",
            configurationDetail: configFileExists ? nil : "必要な設定は左の項目から変更できます",
            cliDetailsTitle: "CLI の詳細"
        )
    }
}
