import SwiftUI
import AgentDomain

public struct StatusLabel: View {
    public let status: SessionStatus
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.status = status
    }

    public var body: some View {
        Text(StatusBadge.localizedLabel(for: status, locale: locale))
            .font(DSFont.caption)
            .foregroundStyle(StatusBadge.color(for: status))
            .fixedSize()
            .help(StatusBadge.helpText(for: status))
    }
}
