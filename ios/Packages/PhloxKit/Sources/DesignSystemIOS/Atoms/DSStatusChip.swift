import SwiftUI
import AgentDomain

/// 仕様の語・色・太さでセッション状態を表示する。待機は表示しない。
public struct DSStatusChip: View {
    let status: SessionStatus
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.status = status
    }

    static func presentation(for status: SessionStatus, locale: Locale) -> IOSStatusPresentation {
        IOSStatusVocabulary.presentation(for: status, locale: locale)
    }

    public var body: some View {
        let resolved = Self.presentation(for: status, locale: locale)
        if let label = resolved.label, let color = resolved.color, let weight = resolved.weight {
            Text(label)
                .font(DSFont.subheadline.weight(weight.fontWeight))
                .foregroundStyle(color)
                .fixedSize()
                .accessibilityLabel(Text(label))
        } else {
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("DSStatusChip") {
    VStack(alignment: .leading, spacing: DSSpacing.s) {
        DSStatusChip(status: .starting)
        DSStatusChip(status: .idle)
        DSStatusChip(status: .running)
        DSStatusChip(status: .awaitingApproval(prompt: "削除を承認しますか？"))
        DSStatusChip(status: .completed(exitCode: 0))
        DSStatusChip(status: .completed(exitCode: 1))
        DSStatusChip(status: .error(message: "接続失敗"))
    }
    .padding(DSSpacing.l)
}
#endif
