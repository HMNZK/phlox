import SwiftUI
import DesignSystemIOS
import PhloxCore

/// カンプ⑧のコピー（テスト可能な契約層）。
enum CodexApprovalCopy {
    static let header = "承認の応答を選択"
    static let accept = "承認する"
    static let acceptForSession = "このセッションは常に許可"
    static let decline = "却下する"
    static let abort = "中止する"
    static let dismiss = "キャンセル"
    /// UI テスト用フォールバック（`ApprovalBarView` 未連携時のカンプ文言）。
    static let uiTestingFallbackPrompt = "add /approvals endpoint · Codex"

    struct MainOption: Equatable {
        let decision: ApprovalDecision
        let title: String
        let isDestructive: Bool
    }

    static let mainOptions: [MainOption] = [
        MainOption(decision: .accept, title: accept, isDestructive: false),
        MainOption(decision: .acceptForSession, title: acceptForSession, isDestructive: false),
        MainOption(decision: .decline, title: decline, isDestructive: true),
        MainOption(decision: .cancel, title: abort, isDestructive: true),
    ]
}

enum CodexApprovalMetrics {
    static let cornerRadius = DSRadius.actionSheet
    static let actionRowHeight = DSTouch.minSize
    static let cardSpacing = DSSpacing.s
}

/// Codex 専用の 4 択シート（カンプ⑧）。accept / decline / acceptForSession / cancel。
public struct CodexApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss

    let approvalID: String
    let prompt: String
    let onDecide: (ApprovalDecision) -> Void

    public init(
        approvalID: String,
        prompt: String = "",
        onDecide: @escaping (ApprovalDecision) -> Void
    ) {
        self.approvalID = approvalID
        self.prompt = prompt
        self.onDecide = onDecide
    }

    public var body: some View {
        VStack(spacing: CodexApprovalMetrics.cardSpacing) {
            mainActionCard
            dismissCard
        }
        .padding(.horizontal, DSSpacing.m)
        .padding(.bottom, DSSpacing.m)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CodexApprovalMetrics.cornerRadius)
        .presentationBackground(.clear)
    }

    private var resolvedPrompt: String {
        if !prompt.isEmpty { return prompt }
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            return CodexApprovalCopy.uiTestingFallbackPrompt
        }
        return ""
    }

    private var mainActionCard: some View {
        VStack(spacing: 0) {
            headerSection
            ForEach(CodexApprovalCopy.mainOptions, id: \.title) { option in
                actionSheetDivider
                actionRow(option)
            }
        }
        .background(DSColor.campSurfaceDialog, in: actionSheetShape)
    }

    private var headerSection: some View {
        VStack(spacing: DSSpacing.xs) {
            Text(CodexApprovalCopy.header)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.campTextQuaternary)
                .accessibilityIdentifier("codexApprovalHeader")

            if !resolvedPrompt.isEmpty {
                Text(resolvedPrompt)
                    .font(DSFont.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.m)
        .padding(.horizontal, DSSpacing.l)
    }

    private func actionRow(_ option: CodexApprovalCopy.MainOption) -> some View {
        Button(role: option.isDestructive ? .destructive : nil) {
            onDecide(option.decision)
        } label: {
            Text(option.title)
                .font(DSFont.headline)
                .foregroundStyle(actionColor(for: option))
                .frame(maxWidth: .infinity, minHeight: CodexApprovalMetrics.actionRowHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(.isButton)
    }

    private func actionColor(for option: CodexApprovalCopy.MainOption) -> Color {
        switch option.decision {
        case .accept:
            return DSColor.statusRunning
        case .acceptForSession:
            return DSColor.accent
        case .decline, .cancel:
            return DSColor.campAttention
        }
    }

    private var dismissCard: some View {
        Button {
            dismiss()
        } label: {
            Text(CodexApprovalCopy.dismiss)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.accent)
                .frame(maxWidth: .infinity, minHeight: CodexApprovalMetrics.actionRowHeight)
        }
        .buttonStyle(.plain)
        .background(DSColor.campSurfaceDialog, in: actionSheetShape)
        .accessibilityLabel(Text(CodexApprovalCopy.dismiss))
        .accessibilityAddTraits(.isButton)
    }

    private var actionSheetDivider: some View {
        Rectangle()
            .fill(DSColor.campCardBorder)
            .frame(height: 1)
    }

    private var actionSheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CodexApprovalMetrics.cornerRadius, style: .continuous)
    }
}

#if DEBUG
#Preview {
    CodexApprovalSheet(
        approvalID: "a1",
        prompt: CodexApprovalCopy.uiTestingFallbackPrompt,
        onDecide: { _ in }
    )
}
#endif
