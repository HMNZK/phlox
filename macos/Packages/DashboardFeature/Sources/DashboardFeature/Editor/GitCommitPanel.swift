import DesignSystem
import SwiftUI

/// 変更の子タブの下端に固定するコミット欄（ADR 0169・07 D2 / D5）。
///
/// 上に 1px の区切り、8×10 の余白。処理の状態・メッセージ欄・コミット / プッシュ / PR を作成と、
/// 押せない理由を右に 1 行。長い git の失敗出力は 1 行目の要約と、84pt で畳んだログに分ける。
struct GitCommitPanel: View {
    @Bindable var viewModel: EditorPanelViewModel
    @ScaledMetric(relativeTo: .body) private var workflowStatusDetailsHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var collapsedLogHeight: CGFloat = 84
    @State private var isLogExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let runningOperation = viewModel.runningOperation {
                runningStatus(runningOperation)
            } else if let workflowStatusMessage = viewModel.workflowStatusMessage {
                workflowStatus(workflowStatusMessage)
            } else if let lastPullRequestURL = viewModel.lastPullRequestURL {
                pullRequestURL(lastPullRequestURL)
            }

            TextField("コミットメッセージ", text: $viewModel.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1...3)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.fieldBorder, lineWidth: 1))
                .accessibilityIdentifier("git-commit-message")
                .disabled(viewModel.isWorkflowBusy)

            workflowActionButtons
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.background)
        .overlay(alignment: .top) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
        .accessibilityIdentifier("git-commit-panel")
    }

    /// 押せない理由（プッシュと PR で同じなら 1 つ）。
    private var unavailableReason: String? {
        var reasons: [String] = []
        for reason in [viewModel.pushAvailabilityReason, viewModel.pullRequestAvailabilityReason].compactMap({ $0 })
        where !reasons.contains(reason) {
            reasons.append(reason)
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: " / ")
    }

    /// 狭い列でもラベルが判別できるよう、理由まで 1 行に収まらなければ理由を下へ、ボタンも収まらなければ縦に積む。
    @ViewBuilder
    private var workflowActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                buttons
                reasonText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { buttons }
                reasonText
            }
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) { buttons }
                reasonText
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        commitButton
        pushButton
        createPullRequestButton
    }

    /// 実行中の状態（07「コミットしています…」）。記号は「…」、面は淡い灰色。
    private func runningStatus(_ operation: GitOperation) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "…")
                .font(DSFont.meta.weight(.bold))
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(Self.runningText(operation))
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DSFont.auxiliary)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("git-workflow-status")
    }

    static func runningText(_ operation: GitOperation) -> LocalizedStringKey {
        switch operation {
        case .commit: "コミットしています…"
        case .push: "プッシュしています…"
        case .pullRequest: "PR を作成しています…"
        }
    }

    @ViewBuilder
    private var reasonText: some View {
        if let unavailableReason {
            Text(verbatim: unavailableReason)
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(Text(verbatim: unavailableReason))
                .accessibilityIdentifier(viewModel.pushAvailabilityReason != nil ? "git-push-unavailable-reason" : "git-pr-unavailable-reason")
        }
    }

    /// 7×9・角丸 7・12pt の箱。失敗は errTint の面に「!」、成功は「✓」。失敗のログは下に畳んで出す。
    private func workflowStatus(_ message: String) -> some View {
        let isError = viewModel.workflowStatusIsError
        let (summary, log) = Self.split(message)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: isError ? "!" : "✓")
                    .font(DSFont.meta.weight(.bold))
                    .foregroundStyle(isError ? DSColor.attentionInk(.error) : DSColor.diffAdded)
                    .accessibilityHidden(true)
                Text(verbatim: summary)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isError, log != nil {
                    Button(isLogExpanded ? "ログを畳む" : "ログをすべて表示") {
                        isLogExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.accentInk)
                    .fixedSize()
                }
                Button {
                    viewModel.dismissWorkflowStatus()
                } label: {
                    Text(verbatim: "✕")
                        .font(.system(size: 10))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help("状態を閉じる")
                .accessibilityLabel("処理状態を閉じる")
                .accessibilityIdentifier("git-workflow-status-dismiss")
            }

            if isError, let log {
                ScrollView {
                    Text(verbatim: log)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(DSColor.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
                .frame(maxHeight: isLogExpanded ? workflowStatusDetailsHeight : collapsedLogHeight)
                .fixedSize(horizontal: false, vertical: true)
                .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: 5))
            }

            if !isError, let lastPullRequestURL = viewModel.lastPullRequestURL {
                pullRequestURL(lastPullRequestURL)
            }
        }
        .font(DSFont.auxiliary)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(isError ? DSColor.attentionTint(.error) : DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("git-workflow-status")
    }

    private func pullRequestURL(_ url: String) -> some View {
        Text(verbatim: url)
            .font(DSFont.monoCaption)
            .foregroundStyle(DSColor.accentInk)
            .textSelection(.enabled)
            .accessibilityIdentifier("git-pr-url")
    }

    /// 「git push が失敗しました:\n<出力>」を要約の 1 行と、git の出力に分ける。
    static func split(_ message: String) -> (summary: String, log: String?) {
        guard let newline = message.firstIndex(of: "\n") else { return (message, nil) }
        var summary = String(message[..<newline])
        if summary.hasSuffix(":") { summary.removeLast() }
        let log = message[message.index(after: newline)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (summary, log.isEmpty ? nil : log)
    }

    private var commitButton: some View {
        // 選んだ件数をボタンに出す（07 の対応表「コミットボタンに件数を出す」）。
        let count = viewModel.pathsSelectedForCommit.count
        let title: LocalizedStringKey = viewModel.runningOperation == .commit ? "コミット中…" : count > 0 ? "コミット（\(count)）" : "コミット"
        return Button(title) {
            Task { await viewModel.commitSelectedPaths() }
        }
        .buttonStyle(.ds(.primary, height: 24, fontSize: 12, padding: 11))
        .disabled(!viewModel.canCommit || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-commit-button")
    }

    private var pushButton: some View {
        Button(viewModel.runningOperation == .push ? "プッシュ中…" : "プッシュ") {
            Task { await viewModel.pushCommittedChanges() }
        }
        .buttonStyle(.ds(.secondary, height: 24, fontSize: 12, padding: 11))
        .disabled(!viewModel.canPush || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-push-button")
    }

    private var createPullRequestButton: some View {
        Button(viewModel.runningOperation == .pullRequest ? "PR を作成中…" : "PR を作成") {
            Task { await viewModel.createPullRequest() }
        }
        .buttonStyle(.ds(.secondary, height: 24, fontSize: 12, padding: 11))
        .disabled(!viewModel.canCreatePullRequest || viewModel.isWorkflowBusy)
        .accessibilityIdentifier("git-create-pr-button")
    }
}

/// 共有スコープで他セッションの変更を誤ってコミットしないための注意（07 D6）。見出しの下の全幅の帯。
struct ChangeScopeNotice: View {
    var body: some View {
        Text("このプロジェクトの全変更を表示しています。ほかのセッションの変更も含まれます。")
            .font(.system(size: 11.5))
            .foregroundStyle(DSColor.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.attentionTint(.approval))
            .overlay(alignment: .bottom) {
                Rectangle().fill(DSColor.separator).frame(height: 1)
            }
            .accessibilityIdentifier("session-change-scope-notice")
    }
}
