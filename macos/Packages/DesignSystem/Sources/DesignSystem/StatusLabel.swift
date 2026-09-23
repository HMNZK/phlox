import SwiftUI
import AgentDomain

/// 一覧の状態の文言。対応待ちの 4 状態だけ太字＋状態色、実行中は中太、ほかは弱い文字。
public struct StatusLabel: View {
    public let state: SessionDisplayState
    public let helpText: String
    /// VoiceOver 用の次の操作（対応待ちのときだけ）。
    let hint: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    /// - Parameters:
    ///   - hasUnseenCompletion: 完了の未読なら「完了」と出す。
    ///   - isStalled: 無応答の判定（チャット型のみ。判定の配線は会話画面の段で入れる）。
    public init(status: SessionStatus, hasUnseenCompletion: Bool = false, isStalled: Bool = false) {
        self.state = SessionDisplayState.resolve(status, hasUnseenCompletion: hasUnseenCompletion, isStalled: isStalled)
        self.helpText = StatusBadge.helpText(for: status)
        self.hint = StatusBadge.nextActionHint(for: status)
    }

    public init(state: SessionDisplayState, helpText: String? = nil) {
        self.state = state
        self.helpText = helpText ?? state.label
        self.hint = nil
    }

    public var body: some View {
        Text(state.localizedLabel(locale: locale))
            .font(DSFont.meta.weight(weight))
            .foregroundStyle(state.color)
            .lineLimit(1)
            .fixedSize()
            .help(helpText)
            .accessibilityLabel(
                [state.localizedLabel(locale: locale), hint].compactMap { $0 }.joined(separator: " — ")
            )
    }

    private var weight: Font.Weight {
        if state.attentionKind != nil { return .semibold }
        return state == .running ? .medium : .regular
    }
}
