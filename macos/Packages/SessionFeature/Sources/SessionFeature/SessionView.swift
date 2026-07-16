import SwiftUI
import AgentDomain
import TerminalUI
import DesignSystem

public struct SessionView: View {
    @Bindable var viewModel: SessionViewModel
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private static let startedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(viewModel: SessionViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.m) {
                AgentSessionIcon(descriptor: viewModel.agentDescriptor, status: viewModel.status, size: 22)
                Text("開始 \(Self.startedAtFormatter.string(from: viewModel.startedAt))")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(DSColor.background)

            TerminalView(coordinator: viewModel.terminalCoordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(DSColor.background)
    }
}
