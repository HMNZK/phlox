import SwiftUI
import Features
import PhloxCore

/// 詳細画面の ViewModel 寿命をナビゲーション push 単位で固定する。
struct SessionDetailDestination: View {
    let session: Session
    let api: PhloxAPI
    let recovery: SessionDetailRecovery?
    let scrollToBottomOnAppear: Bool
    let onDelete: () -> Void

    @State private var detailVM: SessionDetailViewModel

    init(
        session: Session,
        api: PhloxAPI,
        recovery: SessionDetailRecovery? = nil,
        scrollToBottomOnAppear: Bool = true,
        isNewSession: Bool = false,
        initialAttachmentPreviews: [String: [Data]] = [:],
        initialExpandedMessageIDs: Set<String> = [],
        attentionSessions: [Session] = [],
        onShowNextSession: (@MainActor (Session) -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.session = session
        self.api = api
        self.recovery = recovery
        self.scrollToBottomOnAppear = scrollToBottomOnAppear
        self.onDelete = onDelete
        let viewModel = SessionDetailViewModel(
            session: session,
            api: api,
            recovery: recovery,
            isNewSession: isNewSession,
            initialAttachmentPreviews: initialAttachmentPreviews,
            initialExpandedMessageIDs: initialExpandedMessageIDs,
            attentionSessions: attentionSessions,
            onShowNextSession: onShowNextSession
        )
        _detailVM = State(initialValue: viewModel)
    }

#if DEBUG
    init(
        session: Session,
        api: PhloxAPI,
        recovery: SessionDetailRecovery? = nil,
        scrollToBottomOnAppear: Bool = true,
        isNewSession: Bool = false,
        initialAttachmentPreviews: [String: [Data]] = [:],
        initialExpandedMessageIDs: Set<String> = [],
        snapshotReplyState: SessionDetailViewModel.ReplySnapshotState?,
        attentionSessions: [Session] = [],
        onShowNextSession: (@MainActor (Session) -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.session = session
        self.api = api
        self.recovery = recovery
        self.scrollToBottomOnAppear = scrollToBottomOnAppear
        self.onDelete = onDelete
        let viewModel = SessionDetailViewModel(
            session: session,
            api: api,
            recovery: recovery,
            isNewSession: isNewSession,
            initialAttachmentPreviews: initialAttachmentPreviews,
            initialExpandedMessageIDs: initialExpandedMessageIDs,
            attentionSessions: attentionSessions,
            onShowNextSession: onShowNextSession
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
            scrollToBottomOnAppear: scrollToBottomOnAppear,
            onDelete: onDelete
        )
    }
}
