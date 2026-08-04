import SwiftUI

/// エディタパネル変更一覧向けの commit / push / PR 作成 UI（ADR 0169）。
///
/// 狭いドロワー（stacked）でもメッセージ欄とボタンが押せるよう、変更リストの
/// ScrollView の外・下部に置く前提。無効な操作は理由を同じ面に出す。
/// 長い git 失敗出力は高さ上下限付きのテキスト表示にし、閉じる手段を必ず用意する
/// （出力でボタンが画面外へ押し出されると復旧不能になるため。ScrollView は
/// 変更リスト側と競合して高さ 0 に潰れるため使わない）。
struct GitCommitPanel: View {
    @Bindable var viewModel: EditorPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Commit")
                .font(.subheadline.weight(.semibold))

            TextField("Commit message", text: $viewModel.commitMessage, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("git-commit-message")
                .disabled(viewModel.isWorkflowBusy)

            workflowActionButtons

            if let pushAvailabilityReason = viewModel.pushAvailabilityReason {
                Label(pushAvailabilityReason, systemImage: "externaldrive.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("git-push-unavailable-reason")
            }

            if let pullRequestAvailabilityReason = viewModel.pullRequestAvailabilityReason {
                Label(pullRequestAvailabilityReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("git-pr-unavailable-reason")
            }

            if let workflowStatusMessage = viewModel.workflowStatusMessage {
                HStack(alignment: .top, spacing: 6) {
                    Text(workflowStatusMessage)
                        .font(.caption)
                        .foregroundStyle(
                            viewModel.workflowStatusIsError ? .red : .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .frame(
                            height: EditorPanelLayout.commitStatusMaxHeight,
                            alignment: .top
                        )
                        .clipped()
                        .accessibilityIdentifier("git-workflow-status")

                    Button {
                        viewModel.dismissWorkflowStatus()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss status")
                    .accessibilityLabel("Dismiss workflow status")
                    .accessibilityIdentifier("git-workflow-status-dismiss")
                }
            }

            if let lastPullRequestURL = viewModel.lastPullRequestURL {
                Text(lastPullRequestURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("git-pr-url")
            }
        }
        .padding(.top, 2)
        .accessibilityIdentifier("git-commit-panel")
    }

    /// 狭い split 列でもラベルが判別できるよう、横並びが収まるときだけ HStack、
    /// 収まらなければ縦積みへ落とす。
    @ViewBuilder
    private var workflowActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                commitButton
                pushButton
                createPullRequestButton
            }
            .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                commitButton
                pushButton
                createPullRequestButton
            }
            .controlSize(.small)
        }
    }

    private var commitButton: some View {
        Button("Commit") {
            Task { await viewModel.commitSelectedPaths() }
        }
        .disabled(!viewModel.canCommit || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-commit-button")
    }

    private var pushButton: some View {
        Button("Push") {
            Task { await viewModel.pushCommittedChanges() }
        }
        .disabled(!viewModel.canPush || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-push-button")
    }

    private var createPullRequestButton: some View {
        Button("Create PR") {
            Task { await viewModel.createPullRequest() }
        }
        .disabled(!viewModel.canCreatePullRequest || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-create-pr-button")
    }
}
