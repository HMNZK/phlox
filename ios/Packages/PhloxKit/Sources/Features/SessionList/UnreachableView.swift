import SwiftUI
import DesignSystemIOS
import PhloxCore

/// 到達不可の下部カード（カンプ⑩ / DP-4-10）。一覧のスケルトン背後に重ねる。
public struct UnreachableView: View {
    @State private var viewModel: UnreachableViewModel

    public init(viewModel: UnreachableViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: DSIcon.unreachable)
                .font(.title2)
                .foregroundStyle(DSColor.statusError)
                .accessibilityHidden(true)
            Text(viewModel.cardTitle)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.cardMessage)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            if let detail = viewModel.technicalDetail {
                Text(detail)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(DSColor.campTextQuaternary)
                    .multilineTextAlignment(.center)
            }
            DSButton("再接続を試す", variant: .secondary, isLoading: viewModel.isRetrying) {
                Task { await viewModel.retry() }
            }
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: .infinity)
        .background(DSColor.campSurfaceDialog, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(DSColor.campCardBorder, lineWidth: 1)
        )
        .padding(.horizontal, DSSpacing.m)
        .padding(.bottom, DSSpacing.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.unreachableCard)
    }
}

#if DEBUG
#Preview("offlineNetwork") {
    UnreachableView(viewModel: UnreachableViewModel(
        reachability: .offlineNetwork,
        lastUpdated: Date().addingTimeInterval(-180),
        onRetry: {}
    ))
    .background(DSColor.background)
}

#Preview("unreachableHost") {
    UnreachableView(viewModel: UnreachableViewModel(
        reachability: .unreachableHost,
        host: "100.64.0.1",
        lastUpdated: Date().addingTimeInterval(-600),
        onRetry: {}
    ))
    .background(DSColor.background)
}
#endif
