import SwiftUI
import AgentDomain
import PhloxCore

/// 承認 / 却下バー（カンプ③⑧の下部アクション）。承認・却下の 2 択を提示する。
/// Codex 4 択（acceptForSession / cancel 含む）のシートは E4-7 で別途実装する。
public struct DSApprovalBar: View {
    /// このバーが提示する決定（テスト可能な契約）。
    static let offeredDecisions: [ApprovalDecision] = [.decline, .accept]
    /// 却下ボタン variant（カンプ③: ピンク枠・塗りなし）。
    static let declineButtonVariant: DSButton.Variant = .declineOutline
    /// 承認ボタン variant（カンプ③: 緑塗り）。
    static let acceptButtonVariant: DSButton.Variant = .approve

    let approval: Approval
    let onDecide: (ApprovalDecision) -> Void

    public init(approval: Approval, onDecide: @escaping (ApprovalDecision) -> Void) {
        self.approval = approval
        self.onDecide = onDecide
    }

    public var body: some View {
        HStack(spacing: DSSpacing.m) {
            DSButton("却下", variant: Self.declineButtonVariant) { onDecide(.decline) }
            DSButton("承認", variant: Self.acceptButtonVariant, accessibilityIdentifier: AccessibilityID.approvalAccept) {
                onDecide(.accept)
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.bottom, DSSpacing.m)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("DSApprovalBar") {
    DSApprovalBar(approval: Approval(id: "a1", sessionID: "s1", kind: .claudeCode,
                                     prompt: "削除しますか？")) { _ in }
        .padding(DSSpacing.l)
}
#endif
