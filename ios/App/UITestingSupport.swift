import Foundation

/// XCUITest 起動時の引数解釈（`-UITesting` / `-UIScenario=…` / `-UIScreen=…`）。
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

    /// `ios-design.html` の 11 画面（カンプ①〜⑪）に対応。
    enum Screen: String, CaseIterable {
        case connectionSettings
        case sessionList
        case sessionDetail
        case spawn
        case deleteConfirmation
        case launchGate
        case chatAnswer
        case codexApproval
        case spawnError
        case unreachable
        case empty

        var fileName: String {
            switch self {
            case .connectionSettings: "01-connection-settings"
            case .sessionList: "02-session-list"
            case .sessionDetail: "03-session-detail-approval"
            case .spawn: "04-spawn"
            case .deleteConfirmation: "05-delete-confirmation"
            case .launchGate: "06-launch-gate"
            case .chatAnswer: "07-chat-answer"
            case .codexApproval: "08-codex-approval-sheet"
            case .spawnError: "09-spawn-error"
            case .unreachable: "10-unreachable"
            case .empty: "11-empty-state"
            }
        }

        var designLabel: String {
            switch self {
            case .connectionSettings: "① 接続設定"
            case .sessionList: "② セッション一覧"
            case .sessionDetail: "③ セッション詳細・承認"
            case .spawn: "④ 新規タスク（spawn）"
            case .deleteConfirmation: "⑤ 削除確認（カスケード）"
            case .launchGate: "⑥ 起動ゲート（Face ID）"
            case .chatAnswer: "⑦ 質問への回答（send）"
            case .codexApproval: "⑧ 承認の応答（Codex 4 択）"
            case .spawnError: "⑨ spawn 失敗（レート制限）"
            case .unreachable: "⑩ 到達不可（Mac スリープ）"
            case .empty: "⑪ 空状態（初回）"
            }
        }
    }
}
