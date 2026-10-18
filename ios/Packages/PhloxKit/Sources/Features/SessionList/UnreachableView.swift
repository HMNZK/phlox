import DesignSystemIOS
import PhloxCore
import SwiftUI

/// 一覧取得ができないときに本文へ出す説明カード。
public struct UnreachableView: View {
    @State private var viewModel: UnreachableViewModel

    public init(viewModel: UnreachableViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(viewModel.cardTitle)
                .font(DSFont.title.weight(.bold))
                .foregroundStyle(viewModel.reachability == .unreachableHost ? IOSColor.status.error : IOSColor.text.primary)
            Text(viewModel.cardMessage)
                .font(DSFont.subheadline)
                .foregroundStyle(IOSColor.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(viewModel.nextStep)
                .font(DSFont.subheadline)
                .foregroundStyle(IOSColor.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = viewModel.technicalDetail() {
                Text(detail)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(viewModel.footerText())
                .font(DSFont.footnote)
                .foregroundStyle(IOSColor.text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.unreachableCard)
    }
}

#if DEBUG
#Preview("offlineNetwork") {
    UnreachableView(viewModel: UnreachableViewModel(
        reachability: .offlineNetwork,
        lastUpdated: Date().addingTimeInterval(-180)
    ))
    .padding()
    .background(IOSColor.bg.base)
}

#Preview("unreachableHost") {
    UnreachableView(viewModel: UnreachableViewModel(
        reachability: .unreachableHost,
        endpoint: "100.64.0.1:8765",
        lastUpdated: Date().addingTimeInterval(-180)
    ))
    .padding()
    .background(IOSColor.bg.base)
}
#endif
