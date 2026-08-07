import DesignSystem
import SwiftUI

/// エディタパネル変更一覧向けの commit / push / PR 作成 UI（ADR 0169）。
///
/// 狭いドロワー（stacked）でもメッセージ欄とボタンが押せるよう、専用の
/// ScrollView に置く。無効な操作は理由を同じ面に出す。
/// 長い git 失敗出力は要約と展開可能な詳細に分け、詳細部だけを固有高付きでスクロールする。
struct GitCommitPanel: View {
    @Bindable var viewModel: EditorPanelViewModel
    @ScaledMetric(relativeTo: .body) private var workflowStatusDetailsHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var minimumTapTarget: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("コミット")
                .font(DSFont.sectionHeader)

            TextField("コミットメッセージ", text: $viewModel.commitMessage, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("git-commit-message")
                .disabled(viewModel.isWorkflowBusy)

            if case .shared = viewModel.changeScope {
                ChangeScopeNotice()
            }

            workflowActionButtons

            if let pushAvailabilityReason = viewModel.pushAvailabilityReason {
                Label(pushAvailabilityReason, systemImage: "externaldrive.badge.xmark")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("git-push-unavailable-reason")
            }

            if let pullRequestAvailabilityReason = viewModel.pullRequestAvailabilityReason {
                Label(pullRequestAvailabilityReason, systemImage: "exclamationmark.triangle")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("git-pr-unavailable-reason")
            }

            if let workflowStatusMessage = viewModel.workflowStatusMessage {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Label {
                            Text(workflowStatusMessage)
                                .lineLimit(viewModel.workflowStatusIsError ? 2 : nil)
                        } icon: {
                            Image(systemName: viewModel.workflowStatusIsError
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle.fill")
                        }
                        .font(DSFont.caption)
                        .foregroundStyle(viewModel.workflowStatusIsError ? DSColor.statusError : DSColor.textSecondary)

                        if viewModel.workflowStatusIsError {
                            DisclosureGroup("詳細") {
                                ScrollView {
                                    Text(workflowStatusMessage)
                                        .font(DSFont.monoCaption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(height: workflowStatusDetailsHeight)
                                .padding(.top, DSSpacing.xs)
                            }
                            .font(DSFont.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("git-workflow-status")

                    Button {
                        viewModel.dismissWorkflowStatus()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: minimumTapTarget, height: minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("状態を閉じる")
                    .accessibilityLabel("処理状態を閉じる")
                    .accessibilityIdentifier("git-workflow-status-dismiss")
                }
            }

            if let lastPullRequestURL = viewModel.lastPullRequestURL {
                Text(lastPullRequestURL)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("git-pr-url")
            }
        }
        .padding(.top, DSSpacing.xxs)
        .accessibilityIdentifier("git-commit-panel")
    }

    /// 狭い split 列でもラベルが判別できるよう、横並びが収まるときだけ HStack、
    /// 収まらなければ縦積みへ落とす。
    @ViewBuilder
    private var workflowActionButtons: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DSSpacing.s) {
                    commitButton
                    pushButton
                    createPullRequestButton
                }
                .controlSize(.small)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    commitButton
                    pushButton
                    createPullRequestButton
                }
                .controlSize(.small)
            }
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Git処理中")
                .opacity(viewModel.isWorkflowBusy ? 1 : 0)
                .accessibilityHidden(!viewModel.isWorkflowBusy)
            }
    }

    private var commitButton: some View {
        Button("コミット") {
            Task { await viewModel.commitSelectedPaths() }
        }
        .disabled(!viewModel.canCommit || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-commit-button")
    }

    private var pushButton: some View {
        Button("プッシュ") {
            Task { await viewModel.pushCommittedChanges() }
        }
        .disabled(!viewModel.canPush || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-push-button")
    }

    private var createPullRequestButton: some View {
        Button("PRを作成") {
            Task { await viewModel.createPullRequest() }
        }
        .disabled(!viewModel.canCreatePullRequest || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-create-pr-button")
    }
}

/// 共有スコープで他セッションの変更を誤ってコミットしないための注意バナー。
struct ChangeScopeNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DSColor.statusAwaitingApprovalForeground)
            Text("このプロジェクトの全変更を表示しています。他のセッションの変更を含む場合があります。")
                .foregroundStyle(DSColor.textPrimary)
        }
        .font(DSFont.body)
        .padding(DSSpacing.s)
        .background(DSColor.statusAwaitingApprovalFill, in: RoundedRectangle(cornerRadius: DSRadius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m)
                .stroke(DSColor.statusAwaitingApprovalBorder)
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("このプロジェクトの全変更を表示しています。他のセッションの変更を含む場合があります。")
        .accessibilityIdentifier("session-change-scope-notice")
    }
}
