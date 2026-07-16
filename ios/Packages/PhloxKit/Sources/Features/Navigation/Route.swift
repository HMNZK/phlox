import Foundation
import SwiftUI

/// 未 spawn の compose 画面へ渡すプロジェクト識別子（task-1 seam / task-4 が消費）。
public struct SessionComposeDraft: Hashable, Sendable {
    public let project: String

    public init(project: String) {
        self.project = project
    }
}

private struct SessionComposeDraftKey: EnvironmentKey {
    static let defaultValue: SessionComposeDraft? = nil
}

extension EnvironmentValues {
    /// 詳細画面がドラフト compose モードのとき非 nil（task-4 が読み取る）。
    public var sessionComposeDraft: SessionComposeDraft? {
        get { self[SessionComposeDraftKey.self] }
        set { self[SessionComposeDraftKey.self] = newValue }
    }
}

/// アプリ内のスタック遷移・モーダルを型で表す（E4-10）。未定義ルートはコンパイルで弾く。
public enum Route: Hashable, Sendable {
    case sessionDetail(id: String)
    case sessionComposeDraft(project: String)
    case chatAnswer(sessionID: String)
    case settings
    case qrScan
    case deleteConfirmation(id: String, cascadeCount: Int)
}
