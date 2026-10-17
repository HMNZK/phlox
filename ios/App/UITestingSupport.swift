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
        case sessionShell
        case sessionShellNoAttention
        case sessionShellScrolled
        case sessionShellOffline
        case sessionShellDetail
        case list
        case listMulti
        case listCollapsed
        case listChildrenExpanded
        case listAllAttention
        case listLoading
        case listJudging
        case listEmpty
        case listOffNet
        case listOffHost
        case listOffUnknown
        case listError
        case listError401
        case listSE
        case listDT

        var fileName: String {
            switch self {
            case .connectionSettings: "01-connection-settings"
            case .sessionList: "02-session-list"
            case .sessionDetail: "03-session-detail-approval"
            case .deleteConfirmation: "04-delete-confirmation"
            case .launchGate: "05-launch-gate"
            case .unreachable: "06-unreachable"
            case .empty: "07-empty-state"
            case .sessionShell: "08-session-shell"
            case .sessionShellNoAttention: "09-session-shell-no-attention"
            case .sessionShellScrolled: "10-session-shell-scrolled"
            case .sessionShellOffline: "11-session-shell-offline"
            case .sessionShellDetail: "12-session-shell-detail"
            case .list: "13-list"
            case .listMulti: "14-list-multi"
            case .listCollapsed: "15-list-collapsed"
            case .listChildrenExpanded: "16-list-children-expanded"
            case .listAllAttention: "17-list-all-attention"
            case .listLoading: "18-list-loading"
            case .listJudging: "19-list-judging"
            case .listEmpty: "20-list-empty"
            case .listOffNet: "21-list-off-net"
            case .listOffHost: "22-list-off-host"
            case .listOffUnknown: "23-list-off-unknown"
            case .listError: "24-list-error"
            case .listError401: "25-list-error-401"
            case .listSE: "26-list-se"
            case .listDT: "27-list-dynamic-type"
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
            case .sessionShell: "⑧ 下部ナビ（対応待ちあり）"
            case .sessionShellNoAttention: "⑨ 下部ナビ（対応待ちなし）"
            case .sessionShellScrolled: "⑩ 下部ナビ（スクロール）"
            case .sessionShellOffline: "⑪ 下部ナビ（オフライン）"
            case .sessionShellDetail: "⑫ 下部ナビ（セッション画面）"
            case .list: "⑬ 一覧（対応待ち・プロジェクト・子）"
            case .listMulti: "⑭ 一覧（複数プロジェクト）"
            case .listCollapsed: "⑮ 一覧（閉じた欄の内訳）"
            case .listChildrenExpanded: "⑯ 一覧（子セッション展開）"
            case .listAllAttention: "⑰ 一覧（4 種の対応待ち）"
            case .listLoading: "⑱ 一覧（読み込み中）"
            case .listJudging: "⑲ 一覧（接続判定中）"
            case .listEmpty: "⑳ 一覧（空）"
            case .listOffNet: "㉑ 一覧（圏外）"
            case .listOffHost: "㉒ 一覧（Mac 応答なし）"
            case .listOffUnknown: "㉓ 一覧（接続確認中）"
            case .listError: "㉔ 一覧（HTTP 500）"
            case .listError401: "㉕ 一覧（HTTP 401）"
            case .listSE: "㉖ 一覧（375×667）"
            case .listDT: "㉗ 一覧（文字サイズ最大）"
            }
        }

        var snapshotName: String {
            switch self {
            case .list: "List"
            case .listMulti: "ListMulti"
            case .listCollapsed: "ListCollapsed"
            case .listChildrenExpanded: "ListChildrenExpanded"
            case .listAllAttention: "ListAllAttention"
            case .listLoading: "ListLoading"
            case .listJudging: "ListJudging"
            case .listEmpty: "ListEmpty"
            case .listOffNet: "ListOffNet"
            case .listOffHost: "ListOffHost"
            case .listOffUnknown: "ListOffUnknown"
            case .listError: "ListError"
            case .listError401: "ListError401"
            case .listSE: "ListSE"
            case .listDT: "ListDT"
            default: fileName
            }
        }
    }
}
