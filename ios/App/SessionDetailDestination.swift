import SwiftUI
import Features
import PhloxCore

/// 詳細画面の ViewModel 寿命をナビゲーション push 単位で固定する。
/// `navigationDestination` の再評価で `ApprovalViewModel` が作り直されると `.task` がキャンセルされ承認バーが出ないため。
struct SessionDetailDestination: View {
    let session: Session
    let api: PhloxAPI
    let onDelete: () -> Void

    @State private var detailVM: SessionDetailViewModel
    @State private var approvalVM: ApprovalViewModel

    init(session: Session, api: PhloxAPI, onDelete: @escaping () -> Void) {
        self.session = session
        self.api = api
        self.onDelete = onDelete
        _detailVM = State(initialValue: SessionDetailViewModel(session: session, api: api))
        _approvalVM = State(initialValue: ApprovalViewModel(
            sessionID: session.id,
            agentKind: session.agent,
            api: api
        ))
    }

    var body: some View {
        SessionDetailView(
            viewModel: detailVM,
            approvalViewModel: approvalVM,
            onDelete: onDelete
        )
    }
}
