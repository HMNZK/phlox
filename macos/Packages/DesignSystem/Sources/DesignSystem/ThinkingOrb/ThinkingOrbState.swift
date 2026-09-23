import AgentDomain
import Foundation

/// ドメインの活動状態を orb の描画モードと表示ラベルへ写す。
/// ラベルは既存の "Thinking..." と同じ語感（英語・現在進行・三点リーダ）で揃える。
public extension AgentActivityState {
    /// 対応する描画モード。
    var orbMode: OrbMode {
        switch self {
        case .thinking: return .orbits
        case .searching: return .globe
        case .running: return .rubik
        case .editing: return .morph
        case .writing: return .ribbon
        case .waiting: return .wave
        }
    }

    /// 表示言語での状態語（04 A1: 考え中・検索中・実行中・編集中・書き込み中・待機中）。
    /// 文言は App/Localizable.xcstrings（キーは日本語）から、アプリ内の表示言語で引く。
    func orbLabel(locale: Locale) -> String {
        let key: String
        switch self {
        case .thinking: key = "考え中…"
        case .searching: key = "検索中…"
        case .running: key = "実行中…"
        case .editing: key = "編集中…"
        case .writing: key = "書き込み中…"
        case .waiting: key = "待機中…"
        }
        return AppLocalizedString.string(key, locale: locale)
    }
}
