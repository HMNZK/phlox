import SwiftUI
import AgentDomain

/// `StatusBadge` 語彙をカプセル状に表示する（色＋ドット＋アイコン＋文字）。
public struct StatusCapsuleBadge: View {
    public let status: SessionStatus
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.status = status
    }

    public var body: some View {
        CapsuleBadge(
            label: StatusBadge.localizedLabel(for: status, locale: locale),
            iconName: StatusBadge.iconName(for: status),
            tint: StatusBadge.color(for: status)
        )
        .help(StatusBadge.helpText(for: status))
    }
}
