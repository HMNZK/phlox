import Foundation

/// シミュレーターの見本データ起動時の引数解釈（`-UITesting` / `-UIScenario=…` / `-UIScreen=…`）。
enum UITestingSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static var scenario: Scenario {
        let raw = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("-UIScenario=") }?
            .replacingOccurrences(of: "-UIScenario=", with: "") ?? "goldenPath"
        return Scenario(rawValue: raw) ?? .goldenPath
    }

    /// スクリーンショット検証用の画面指定（`-UIScreen=sessionList` 等）。未指定時は `nil`。
    static var screen: Screen? {
        guard isEnabled else { return nil }
        let raw = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("-UIScreen=") }?
            .replacingOccurrences(of: "-UIScreen=", with: "")
        guard let raw, let screen = Screen(rawValue: raw) else { return nil }
        return screen
    }

    enum Scenario: String {
        case goldenPath
        case empty
        case launchGate
    }

    enum Screen: String, CaseIterable {
        case connectionSettings
        case sessionList
        case sessionDetail
        case deleteConfirmation
        case launchGate
        case unreachable
        case empty

        var fileName: String {
            switch self {
            case .connectionSettings: "01-connection-settings"
            case .sessionList: "02-session-list"
            case .sessionDetail: "03-session-detail-approval"
            case .deleteConfirmation: "04-delete-confirmation"
            case .launchGate: "05-launch-gate"
            case .unreachable: "06-unreachable"
            case .empty: "07-empty-state"
            }
        }

        var designLabel: String {
            switch self {
            case .connectionSettings: "① 接続設定"
            case .sessionList: "② セッション一覧"
            case .sessionDetail: "③ セッション詳細・承認"
            case .deleteConfirmation: "④ 削除確認（カスケード）"
            case .launchGate: "⑤ 起動ゲート（Face ID）"
            case .unreachable: "⑥ 到達不可（Mac スリープ）"
            case .empty: "⑦ 空状態（初回）"
            }
        }
    }
}
