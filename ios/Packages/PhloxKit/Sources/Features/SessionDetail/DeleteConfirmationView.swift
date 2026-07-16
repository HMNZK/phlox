import SwiftUI
import DesignSystemIOS
import PhloxCore

/// カンプ⑤の暗転オーバーレイ不透明度。design.md §5 ⑤ brightness .45。
enum DeleteConfirmationMetrics {
    static let backdropBrightness = DSColor.campModalBackdropBrightness
    static let backdropOverlayOpacity = DSColor.campModalBackdropOpacity
}

/// カンプ⑤の文言（テスト可能なコピー層）。
enum DeleteConfirmationCopy {
    static let title = "セッションを削除しますか？"

    static func body(cascadeCount: Int) -> String {
        if cascadeCount > 0 {
            return "このセッションと 子孫 \(cascadeCount) 件 が Mac 側で削除されます。元に戻せません。"
        }
        return "このセッションが Mac 側で削除されます。元に戻せません。"
    }

    static func deleteButtonLabel(totalCount: Int) -> String {
        "削除（\(totalCount)件）"
    }
}

/// 削除確認の中央アラート（カンプ⑤）。暗転オーバーレイ上にダイアログを表示し単段で削除する。
public struct DeleteConfirmationView: View {
    @State private var viewModel: DeleteConfirmationViewModel
    private let onCancel: () -> Void

    public init(viewModel: DeleteConfirmationViewModel, onCancel: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onCancel = onCancel
    }

    private var totalDeleteCount: Int { viewModel.cascadeCount + 1 }

    public var body: some View {
        ZStack {
            DSColor.campModalBackdrop
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .onTapGesture { onCancel() }

            dialogCard
                .padding(.horizontal, DSSpacing.l)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .animation(DSMotion.easeOut, value: viewModel.isDeleting)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var dialogCard: some View {
        VStack(spacing: DSSpacing.m) {
            trashIcon

            Text(DeleteConfirmationCopy.title)
                .font(DSFont.title2)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("deleteConfirmationTitle")

            cascadeBodyText
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.campTextQuaternary)
                .multilineTextAlignment(.center)

            if case .failed(let message) = viewModel.state {
                DSResultBanner(message: message, isError: true)
            }

            DSButton(
                DeleteConfirmationCopy.deleteButtonLabel(totalCount: totalDeleteCount),
                variant: .destructive,
                isLoading: viewModel.isDeleting
            ) {
                Task { await viewModel.confirmDelete() }
            }

            Button("キャンセル", action: onCancel)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.accent)
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
                .accessibilityAddTraits(.isButton)
        }
        .padding(DSSpacing.l)
        .background(
            DSColor.campSurfaceDialog,
            in: RoundedRectangle(cornerRadius: DSRadius.dialog, style: .continuous)
        )
        .shadow(
            color: DSShadow.dialog.color,
            radius: DSShadow.dialog.radius,
            x: DSShadow.dialog.x,
            y: DSShadow.dialog.y
        )
    }

    private var trashIcon: some View {
        ZStack {
            Circle()
                .fill(DSColor.campAttention.opacity(0.18))
            Image(systemName: DSIcon.delete)
                .font(DSFont.title2)
                .foregroundStyle(DSColor.campAttention)
        }
        .frame(width: DSTouch.rowMinHeight, height: DSTouch.rowMinHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var cascadeBodyText: some View {
        if viewModel.cascadeCount > 0 {
            let count = viewModel.cascadeCount
            (Text("このセッションと ")
                + Text("子孫 \(count) 件").fontWeight(.semibold)
                + Text(" が Mac 側で削除されます。元に戻せません。"))
        } else {
            Text(DeleteConfirmationCopy.body(cascadeCount: 0))
        }
    }
}

#if DEBUG
#Preview("Cascade") {
    ZStack {
        DSColor.background.ignoresSafeArea()
        DeleteConfirmationView(
            viewModel: DeleteConfirmationViewModel(sessionID: "s1", cascadeCount: 3, api: StubPhloxAPI(), onDeleted: {}),
            onCancel: {}
        )
    }
}
#endif
