import SwiftUI
import DesignSystemIOS
import PhloxCore

/// 承認/却下バー（カンプ③⑧）。`DSApprovalRequestCard` + アクションボタンを awaitingApproval スロットに埋め込む。
public struct ApprovalBarView: View {
    @Bindable var viewModel: ApprovalViewModel

    public init(viewModel: ApprovalViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if let message = viewModel.resultMessage {
                DSResultBanner(message: message, isError: false)
            } else if viewModel.isVisible, let approval = viewModel.approvals.first {
                VStack(spacing: DSSpacing.s) {
                    if let error = viewModel.errorMessage {
                        DSResultBanner(message: error, isError: true)
                    }
                    DSApprovalRequestCard(approval: approval)
                    DSApprovalBar(approval: approval) { decision in
                        Task { await viewModel.tapPrimary(approvalID: approval.id, decision: decision) }
                    }
                }
                .sheet(isPresented: $viewModel.showCodexSheet) {
                    CodexApprovalSheet(approvalID: approval.id) { decision in
                        Task { await viewModel.respond(decision, approvalID: approval.id) }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("ClaudeCode") {
    ApprovalBarView(viewModel: ApprovalViewModel(
        sessionID: "s1", agentKind: .claudeCode,
        api: StubPhloxAPI(approvals: [Approval(id: "a1", sessionID: "s1", kind: .claudeCode, prompt: "削除しますか？")])
    ))
    .padding(DSSpacing.l)
}
#endif
