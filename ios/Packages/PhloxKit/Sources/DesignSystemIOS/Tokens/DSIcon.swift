import Foundation

/// アプリで使う SF Symbols 名を定数管理する。生の文字列リテラル散在を防ぎ、
/// シンボル名の変更を 1 箇所に閉じる。状態/エージェント固有アイコンは共有 DesignSystem の
/// `StatusBadge.iconName(for:)` / `AgentRegistry.descriptor(for:).symbolName` を使うこと。
public enum DSIcon {
    // ナビ・アクション
    public static let sessions = "bubble.left.and.bubble.right.fill"
    public static let spawn = "plus.circle.fill"
    public static let send = "arrow.up.circle.fill"
    public static let delete = "trash"
    public static let settings = "gearshape"
    public static let close = "xmark"
    public static let clear = "xmark.circle.fill"
    public static let chevron = "chevron.right"

    // 接続・到達性
    public static let reachable = "wifi"
    public static let unreachable = "wifi.slash"
    public static let connectionTest = "antenna.radiowaves.left.and.right"

    // 起動ゲート・セキュリティ
    public static let faceID = "faceid"
    public static let lock = "lock.fill"

    // 承認
    public static let approve = "checkmark"
    public static let decline = "xmark"

    // 状態表現（空状態など）
    public static let empty = "tray"
    public static let errorBadge = "exclamationmark.triangle.fill"
}
