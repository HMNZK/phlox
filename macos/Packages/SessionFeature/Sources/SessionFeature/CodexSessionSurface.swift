import SwiftUI
import AgentDomain
import DesignSystem

/// Codex の子エージェントの取得エラー。計画（update_plan）は会話ログのタスクのスナップショットとして
/// エージェント状態カードに出す（AgentStatusCardView）ので、ここには出さない。子エージェントは共通の strip / marker で表示する。
enum CodexSessionSurfaceAccessibilityID {
    static let root = "CodexSessionSurface"
    static let subAgentError = "CodexSubAgent.error"
}

struct CodexSessionSurface: View {
    @Bindable var viewModel: ChatSessionViewModel
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var hasContent: Bool { viewModel.codexSubAgentError != nil }

    var body: some View {
        let _ = themeID
        if viewModel.agentRef == .builtin(.codex) {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.codexSubAgentError != nil {
                    ErrorMessageCell(message: "サブエージェント情報を取得できませんでした", timestamp: Date())
                        .padding(8)
                        .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.subAgentError)
                }
            }
            .background {
                if hasContent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSColor.cardBackground)
                }
            }
            .overlay {
                if hasContent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DSColor.separator, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier(CodexSessionSurfaceAccessibilityID.root)
        }
    }
}
