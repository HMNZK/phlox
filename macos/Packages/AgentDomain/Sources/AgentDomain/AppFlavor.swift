import Foundation

/// アプリのビルド種別。Release と Debug でデータ保存先・Keychain を分離するための識別子。
public enum AppFlavor: Sendable, Equatable {
    case release
    case debug

    /// 現在のビルド構成に対応する flavor。Debug ビルド時のみ `.debug`。
    public static var current: AppFlavor {
        #if DEBUG
        return .debug
        #else
        return .release
        #endif
    }

    /// アプリの人間可読な表示名（設定画面・メニューバー表示の正本）。
    /// 契約: tasks/task-10.md（受け入れテスト AppFlavorDisplayNameAcceptanceTests が凍結）。
    public var displayName: String {
        switch self {
        case .release: return "Phlox"
        case .debug: return "Phlox (Debug)"
        }
    }

    /// `~/Library/Application Support/` 直下のルートディレクトリ名。
    public var appSupportDirectoryName: String {
        switch self {
        case .release: return "Phlox"
        case .debug: return "Phlox-Debug"
        }
    }

    /// mobile token を保存する Keychain service 名。
    public var mobileTokenKeychainService: String {
        switch self {
        case .release: return "com.phlox.Phlox.mobileToken"
        case .debug: return "com.phlox.Phlox.debug.mobileToken"
        }
    }

    /// レガシー移行（AgentDashboard → 現行データディレクトリ）を実行してよいか。
    /// Debug は常に空から始めるため false（既存の Release データを取り込まない）。
    public var runsLegacyMigration: Bool {
        switch self {
        case .release: return true
        case .debug: return false
        }
    }
}
