import Foundation

/// 新規チャットの入口から引き継ぐ、任意の初期プロジェクト。
public struct SessionComposeDraft: Hashable, Sendable {
    public let project: String
    public let projectID: String?

    public init(project: String, projectID: String? = nil) {
        self.project = project
        self.projectID = projectID
    }
}

/// アプリ内のスタック遷移・モーダルを型で表す（E4-10）。未定義ルートはコンパイルで弾く。
public enum Route: Hashable, Sendable {
    case sessionDetail(id: String)
    case newChat(SessionComposeDraft)
    case settings
    case qrScan
    case deleteConfirmation(id: String, cascadeCount: Int)
}
