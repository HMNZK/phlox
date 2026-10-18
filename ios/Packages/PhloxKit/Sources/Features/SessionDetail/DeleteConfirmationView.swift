import SwiftUI
import PhloxCore

/// OS 標準の削除確認と、削除実行中の操作ブロック。
public struct DeleteConfirmationView: View {
    private enum AlertItem: Identifiable {
        case confirmation
        case failure(String)

        var id: String {
            switch self {
            case .confirmation: "confirmation"
            case .failure: "failure"
            }
        }
    }

    @State private var viewModel: DeleteConfirmationViewModel
    @State private var alert: AlertItem? = .confirmation
    private let onCancel: () -> Void

    public init(viewModel: DeleteConfirmationViewModel, onCancel: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onCancel = onCancel
    }

    public var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                if viewModel.isDeleting {
                    ZStack {
                        Color.black.opacity(0.28).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("削除しています…")
                                .font(.body)
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isModal)
                }
            }
            .alert(item: $alert) { item in
                switch item {
                case .confirmation:
                    Alert(
                        title: Text(viewModel.title),
                        message: Text(viewModel.message),
                        primaryButton: .destructive(Text(viewModel.deleteButtonLabel)) {
                            Task { await viewModel.confirmDelete() }
                        },
                        secondaryButton: .cancel(Text("キャンセル"), action: onCancel)
                    )
                case .failure(let message):
                    Alert(
                        title: Text("削除できませんでした"),
                        message: Text(message),
                        primaryButton: .default(Text("もう一度削除")) {
                            Task { await viewModel.confirmDelete() }
                        },
                        secondaryButton: .cancel(Text("閉じる"), action: onCancel)
                    )
                }
            }
            .onChange(of: viewModel.state) { _, state in
                if case .failed(let message) = state {
                    alert = .failure(message)
                }
            }
    }
}
