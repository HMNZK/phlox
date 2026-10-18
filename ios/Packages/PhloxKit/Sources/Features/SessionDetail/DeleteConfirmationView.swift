import SwiftUI
import PhloxCore

/// OS 標準の削除確認と、削除実行中の操作ブロック。
public struct DeleteConfirmationView: View {
    private enum AlertItem: Identifiable {
        case confirmation
        case failure(ErrorPresentation)

        var id: String {
            switch self {
            case .confirmation: "confirmation"
            case .failure(let presentation): "failure-\(presentation.technicalDetail ?? "")"
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
                case .failure(let presentation):
                    Alert(
                        title: Text(presentation.title),
                        message: failureMessage(presentation),
                        primaryButton: .default(Text(presentation.recoveryAction ?? "もう一度削除")) {
                            Task { await viewModel.confirmDelete() }
                        },
                        secondaryButton: .cancel(Text("閉じる"), action: onCancel)
                    )
                }
            }
            .onChange(of: viewModel.state) { _, state in
                if case .failed = state, let presentation = viewModel.failurePresentation {
                    alert = .failure(presentation)
                }
            }
    }

    private func failureMessage(_ presentation: ErrorPresentation) -> Text {
        var message = AttributedString([presentation.cause, presentation.nextStep].joined(separator: "\n"))
        if let technicalDetail = presentation.technicalDetail {
            var detail = AttributedString("\n\(technicalDetail)")
            detail.font = .system(.footnote, design: .monospaced)
            message.append(detail)
        }
        return Text(message)
    }
}
