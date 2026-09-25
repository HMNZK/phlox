import DesignSystem
import Foundation

// task-16 契約の PM スタブ。API 表面は受け入れテスト
// ClaudeUsageVisibilityAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-16.md

/// Claude Usage データの鮮度注記。statusLine はターミナルセッションでしか発火しない
/// （チャットモードでは供給が止まる）ため、stale/未取得を理由つきで可視化する。
enum ClaudeUsageStaleness {
    static let staleAfter: TimeInterval = 30 * 60
    private static let hourInterval: TimeInterval = 60 * 60
    private static let dayInterval: TimeInterval = 24 * hourInterval

    /// nil = 新鮮（注記なし）。それ以外は行に添える注記テキスト（見本「43 分前に取得 · 古い可能性」）。日本語。
    static func note(now: Date, dataAsOf: Date?) -> String? {
        note(now: now, dataAsOf: dataAsOf, locale: Locale(identifier: "ja"))
    }

    /// 表示言語つき（アプリの言語設定は SwiftUI の locale にだけ入るので、呼び出し側から渡す）。
    static func note(now: Date, dataAsOf: Date?, locale: Locale) -> String? {
        guard let dataAsOf else {
            return AppLocalizedString.string("未取得（ターミナルの Claude セッション実行時に更新されます）", locale: locale)
        }

        let elapsed = now.timeIntervalSince(dataAsOf)
        guard elapsed >= staleAfter else { return nil }

        let (count, key): (Int, String) =
            if elapsed < hourInterval { (Int(elapsed / 60), "%lld 分前に取得 · 古い可能性") }
            else if elapsed < dayInterval { (Int(elapsed / hourInterval), "%lld 時間前に取得 · 古い可能性") }
            else { (Int(elapsed / dayInterval), "%lld 日前に取得 · 古い可能性") }
        return String(format: AppLocalizedString.string(key, locale: locale), count)
    }
}
