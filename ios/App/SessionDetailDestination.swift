import SwiftUI
import Features
import PhloxCore

/// 詳細画面の ViewModel 寿命をナビゲーション push 単位で固定する。
struct SessionDetailDestination: View {
    let session: Session
    let api: PhloxAPI
    let recovery: SessionDetailRecovery?
    let onDelete: () -> Void

    @State private var detailVM: SessionDetailViewModel

    init(
        session: Session,
        api: PhloxAPI,
        recovery: SessionDetailRecovery? = nil,
        isNewSession: Bool = false,
        initialAttachmentPreviews: [String: [Data]] = [:],
        initialExpandedMessageIDs: Set<String> = [],
        onDelete: @escaping () -> Void
    ) {
        self.session = session
        self.api = api
        self.recovery = recovery
        self.onDelete = onDelete
        let viewModel = SessionDetailViewModel(
            session: session,
            api: api,
            recovery: recovery,
            isNewSession: isNewSession,
            initialAttachmentPreviews: initialAttachmentPreviews,
            initialExpandedMessageIDs: initialExpandedMessageIDs
        )
        _detailVM = State(initialValue: viewModel)
    }

#if DEBUG
    init(
        session: Session,
        api: PhloxAPI,
        recovery: SessionDetailRecovery? = nil,
        isNewSession: Bool = false,
        initialAttachmentPreviews: [String: [Data]] = [:],
        initialExpandedMessageIDs: Set<String> = [],
        snapshotReplyState: SessionDetailViewModel.ReplySnapshotState?,
        onDelete: @escaping () -> Void
    ) {
        self.session = session
        self.api = api
        self.recovery = recovery
        self.onDelete = onDelete
        let viewModel = SessionDetailViewModel(
            session: session,
            api: api,
            recovery: recovery,
            isNewSession: isNewSession,
            initialAttachmentPreviews: initialAttachmentPreviews,
            initialExpandedMessageIDs: initialExpandedMessageIDs
        )
        if let snapshotReplyState {
            viewModel.configureReplySnapshot(snapshotReplyState)
        }
        _detailVM = State(initialValue: viewModel)
    }
#endif

    var body: some View {
        SessionDetailView(
            viewModel: detailVM,
            onDelete: onDelete
        )
    }
}
