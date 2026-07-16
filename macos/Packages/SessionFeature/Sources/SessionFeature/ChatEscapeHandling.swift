import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem

/// esc の View レベル分岐（task-9）。composer フォーカス時（NSTextView.keyDown）と
/// 非フォーカス時（.onKeyPress(.escape)）の双方から同一経路で呼ばれ、優先順を一元化する:
/// (1) ピッカー表示中は閉じる → (2) サブエージェントドロワーが開いていれば閉じる（既存挙動）
/// → (3) esc 状態機械（単発=interrupt / 2連打=ピッカー）。
/// 状態機械そのもの（2連打判定・時刻記録）は ViewModel.handleEscapeKey に委ねる。
@MainActor
func performChatEscape(_ viewModel: ChatSessionViewModel) {
    if viewModel.isHistoryPickerPresented {
        viewModel.handleEscapeKey()
        return
    }
    if viewModel.selectedSubAgentId != nil {
        viewModel.selectSubAgent(nil)
        return
    }
    viewModel.handleEscapeKey()
}

/// 単一表示・グリッド両方の chat ビューへ、esc 状態機械（非フォーカス経路）・履歴ピッカー
/// overlay・下書き復元を一括で付与する（task-9）。composer フォーカス時の esc は
/// SubmitAwareTextView.keyDown が消費するため、.onKeyPress(.escape) は非フォーカス時のみ発火する。
private struct ChatEscapeHandling: ViewModifier {
    let viewModel: ChatSessionViewModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                performChatEscape(viewModel)
                return .handled
            }
            .onChange(of: viewModel.draftRestoration) { _, newValue in
                guard let newValue else { return }
                viewModel.draft = newValue
                viewModel.consumeDraftRestoration()
            }
            .overlay {
                if viewModel.isHistoryPickerPresented {
                    ZStack {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.handleEscapeKey() }
                        ChatHistoryRevertPicker(
                            candidates: viewModel.revertCandidates,
                            onConfirm: { id in
                                Task { await viewModel.confirmRevert(toUserMessageID: id) }
                            },
                            onCancel: { viewModel.handleEscapeKey() }
                        )
                        .padding(DSSpacing.xl)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: viewModel.isHistoryPickerPresented)
    }
}

extension View {
    func chatEscapeHandling(viewModel: ChatSessionViewModel) -> some View {
        modifier(ChatEscapeHandling(viewModel: viewModel))
    }
}

extension SessionStatus {
    var isRunning: Bool {
        switch self {
        case .running, .awaitingApproval:
            true
        case .starting, .idle, .completed, .error:
            false
        }
    }
}
