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

    /// orb の右に出す状態語。
    var orbLabel: String {
        switch self {
        case .thinking: return "Thinking..."
        case .searching: return "Searching..."
        case .running: return "Running..."
        case .editing: return "Editing..."
        case .writing: return "Writing..."
        case .waiting: return "Waiting..."
        }
    }
}
