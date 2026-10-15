import DesignSystem
import SwiftUI

/// Git タブの上部に固定するコミット欄（ADR 0204）。
///
/// メッセージ・主ボタン・理由・プッシュ / PR の順。失敗は下端に 3 行で表示し、詳細を開ける。
struct GitCommitPanel: View {
    @Bindable var viewModel: EditorPanelViewModel
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle
    @State private var isLogExpanded = false
    @FocusState private var messageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.chip) {
            TextField(text: $viewModel.commitMessage, axis: .vertical) {
                Text("コミットメッセージ", bundle: bundle)
            }
                .textFieldStyle(.plain)
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1...5)
                .padding(.vertical, DSSpacing.chip)
                .padding(.horizontal, DSSpacing.s)
                .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.fieldBorder, lineWidth: DSLayout.paneSeparatorWidth))
                .accessibilityLabel(Text("コミットメッセージ", bundle: bundle))
                .accessibilityIdentifier("git-commit-message")
                .focused($messageFocused)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers == .command else { return .ignored }
                    Task { await viewModel.commitStagedChanges() }
                    return .handled
                }
                .disabled(viewModel.isWorkflowBusy)

            workflowActionButtons
            if let runningOperation = viewModel.runningOperation {
                runningStatus(runningOperation)
            } else if let workflowStatusMessage = viewModel.workflowStatusMessage {
                workflowStatus(workflowStatusMessage)
            } else if let lastPullRequestURL = viewModel.lastPullRequestURL {
                pullRequestURL(lastPullRequestURL)
            }
        }
        .padding(.vertical, DSSpacing.s)
        .padding(.horizontal, DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.background)
        .overlay(alignment: .top) {
            Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth)
        }
        .accessibilityIdentifier("git-commit-panel")
        .onChange(of: messageFocused) { _, focused in viewModel.commitMessageFocused = focused }
        .onDisappear { viewModel.commitMessageFocused = false }
        .onChange(of: viewModel.workflowStatusMessage) { _, _ in isLogExpanded = false }
        .onAppear { if viewModel.takeCommitFocusRequest() { messageFocused = true } }
        .onChange(of: viewModel.commitFocusToken) { _, token in
            if token > 0, viewModel.takeCommitFocusRequest() { messageFocused = true }
        }
    }

    private var commitReason: String {
        if !viewModel.conflictedPaths.isEmpty { return localized("競合をターミナルなどで解消してください") }
        if viewModel.stagedChanges.isEmpty { return localized("変更をステージしてください") }
        if viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized("コミットメッセージを入力してください")
        }
        return String(format: localized("%lld ファイルをコミット"), viewModel.stagedChanges.count)
    }
    private func localized(_ key: String) -> String { AppLocalizedString.string(key, locale: locale, bundle: bundle) }

    private var workflowActionButtons: some View {
        VStack(alignment: .leading, spacing: DSSpacing.chip) {
            commitButton
            Text(verbatim: commitReason).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                .lineLimit(1).truncationMode(.tail).help(Text(verbatim: commitReason))
                .accessibilityIdentifier("git-commit-reason")
            HStack(spacing: DSSpacing.s) { pushButton; createPullRequestButton }
        }
    }

    /// 実行中の状態（07「コミットしています…」）。記号は「…」、面は淡い灰色。
    private func runningStatus(_ operation: GitOperation) -> some View {
        HStack(spacing: DSSpacing.s) {
            Text(verbatim: "…")
                .font(DSFont.meta.weight(.bold))
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(Self.runningText(operation), bundle: bundle)
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DSFont.auxiliary)
        .padding(.vertical, DSSpacing.s)
        .padding(.horizontal, DSSpacing.s)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.m))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("git-workflow-status")
    }

    static func runningText(_ operation: GitOperation) -> LocalizedStringKey {
        switch operation {
        case .fetch: "取得しています…"
        case .stash: "スタッシュを操作しています…"
        case .branch: "ブランチを操作しています…"
        case .commit: "コミットしています…"
        case .push: "プッシュしています…"
        case .pullRequest: "PR を作成しています…"
        case .stage: "ステージしています…"
        case .unstage: "ステージを外しています…"
        }
    }

    /// 失敗は 3 行に畳み、入力中のメッセージ欄を押し下げず下端に出す。
    private func workflowStatus(_ message: String) -> some View {
        let isError = viewModel.workflowStatusIsError
        return VStack(alignment: .leading, spacing: DSSpacing.chip) {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(isError ? DSColor.attentionInk(.error) : DSColor.diffAdded)
                    .accessibilityHidden(true)
                Group {
                    if isLogExpanded {
                        ScrollView {
                            Text(verbatim: message)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: DSLayout.gitWorkflowDetailsMaximumHeight)
                    } else {
                        Text(verbatim: message).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
                Button { viewModel.dismissWorkflowStatus() } label: {
                    Image(systemName: "xmark").font(DSFont.meta).frame(width: DSSpacing.xl, height: DSSpacing.xl)
                }.buttonStyle(HoverableIconButtonStyle())
                    .help(Text("状態を閉じる", bundle: bundle))
                    .accessibilityLabel(Text("処理状態を閉じる", bundle: bundle))
                    .accessibilityIdentifier("git-workflow-status-dismiss")
            }
            if isError {
                Button { isLogExpanded.toggle() } label: { Text(isLogExpanded ? "詳細を閉じる" : "詳細", bundle: bundle) }
                    .buttonStyle(.plain).font(DSFont.meta).underline()
                    .accessibilityLabel(Text(isLogExpanded ? "詳細を閉じる" : "詳細", bundle: bundle))
                    .accessibilityIdentifier("git-workflow-status-details")
            }
            if !isError, let lastPullRequestURL = viewModel.lastPullRequestURL { pullRequestURL(lastPullRequestURL) }
        }.padding(DSSpacing.s)
            .background(isError ? DSColor.attentionTint(.error) : DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.m))
            .accessibilityElement(children: .contain).accessibilityIdentifier("git-workflow-status")
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
        Button { Task { await viewModel.commitStagedChanges() } } label: {
            Text(viewModel.runningOperation == .commit ? "コミット中…" : "コミット", bundle: bundle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ds(.primary, height: DSLayout.gitRowHeight, fontSize: DSFont.bodyPointSize, padding: DSSpacing.s))
        .disabled(!viewModel.canCommit || viewModel.isWorkflowBusy)
        .accessibilityLabel(Text("コミット", bundle: bundle)).accessibilityIdentifier("git-commit-button")
    }

    private var pushButton: some View {
        Button { Task { await viewModel.pushCommittedChanges() } } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(viewModel.runningOperation == .push ? "プッシュ中…" : "プッシュ", bundle: bundle)
                if viewModel.aheadCount > 0 { Text(verbatim: "↑\(viewModel.aheadCount)") }
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.ds(.secondary, height: DSLayout.gitRowHeight, fontSize: DSFont.bodyPointSize, padding: DSSpacing.s))
        .disabled(!viewModel.canPush || viewModel.isWorkflowBusy)
        .help(Text(verbatim: viewModel.pushAvailabilityReason ?? localized(viewModel.hasUpstream ? "プッシュ" : "プッシュ（追跡先を作る）")))
        .accessibilityLabel(Text("プッシュ", bundle: bundle)).accessibilityIdentifier("git-push-button")
    }

    private var createPullRequestButton: some View {
        Button { Task { await viewModel.createPullRequest() } } label: {
            Text(viewModel.runningOperation == .pullRequest ? "PR を作成中…" : "PR を作成", bundle: bundle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ds(.secondary, height: DSLayout.gitRowHeight, fontSize: DSFont.bodyPointSize, padding: DSSpacing.s))
        .disabled(!viewModel.canCreatePullRequest || viewModel.isWorkflowBusy)
        .help(Text(verbatim: viewModel.pullRequestAvailabilityReason ?? localized("PR を作成")))
        .accessibilityLabel(Text("PR を作成", bundle: bundle)).accessibilityIdentifier("git-create-pr-button")
    }
}

/// 共有スコープで他セッションの変更を誤ってコミットしないための注意（07 D6）。見出しの下の全幅の帯。
struct ChangeScopeNotice: View {
    @Environment(\.localizationBundle) private var bundle
    var body: some View {
        Text("このプロジェクトの全変更を表示しています。ほかのセッションの変更も含まれます。", bundle: bundle)
            .font(DSFont.auxiliary)
            .foregroundStyle(DSColor.textPrimary)
            .lineSpacing(DSSpacing.xxs)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, DSSpacing.chip)
            .padding(.horizontal, DSSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.attentionTint(.approval))
            .overlay(alignment: .bottom) {
                Rectangle().fill(DSColor.separator).frame(height: DSLayout.paneSeparatorWidth)
            }
            .accessibilityIdentifier("session-change-scope-notice")
    }
}
