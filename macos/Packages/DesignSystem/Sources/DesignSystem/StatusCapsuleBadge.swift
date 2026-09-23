import SwiftUI
import AgentDomain

/// セッションヘッダの状態表示。対応待ちは状態色のカプセル、それ以外は無彩色の文字だけ。
public struct StatusCapsuleBadge: View {
    public let state: SessionDisplayState
    /// 「3分」「2:14」などの経過表示。対応待ちのときだけ ` · ` で続ける。
    public let elapsed: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.init(state: SessionDisplayState.resolve(status))
    }

    public init(state: SessionDisplayState, elapsed: String? = nil) {
        self.state = state
        self.elapsed = elapsed
    }

    public var body: some View {
        let label = state.localizedLabel(locale: locale)
        if let kind = state.attentionKind {
            CapsuleBadge(
                label: elapsed.map { "\(label) · \($0)" } ?? label,
                ink: DSColor.attentionInk(kind),
                tint: DSColor.attentionTint(kind)
            )
        } else {
            Text(label)
                .font(DSFont.auxiliary.weight(state == .running ? .medium : .regular))
                .foregroundStyle(state == .running ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
