import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

/// 会話画面の下端（05）。上から 送信失敗の通知 → 承認カード → 質問カード → 入力欄 → キーの案内。
/// 承認と質問は会話の中に流さず、入力欄の直上に出す。カードが出ても入力欄のフォーカスは動かさない。
struct ChatReplyArea<Composer: View>: View {
    @Bindable var viewModel: ChatSessionViewModel
    var showsKeyHints = true
    /// 承認カードの「差分を見る」（会話の該当のファイルの変更へ移って開く）。
    var onShowDiff: ((String) -> Void)? = nil
    let onRetrySend: () -> Void
    @ViewBuilder let composer: () -> Composer

    @State private var isCardFocused = false
    @State private var isQuestionFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                if let failure = viewModel.sendFailure {
                    SendFailureNotice(failure: failure, onRetry: onRetrySend) {
                        viewModel.dismissSendFailure()
                    }
                }
                let approvals = viewModel.replyApprovals
                if let approval = viewModel.currentReplyApproval {
                    ApprovalCard(
                        viewModel: viewModel,
                        approval: approval,
                        index: approvals.firstIndex { $0.id == approval.id } ?? 0,
                        count: approvals.count,
                        onFocusChange: { isCardFocused = $0 },
                        onShowDiff: onShowDiff
                    )
                    .id(approval.id)
                }
                if let question = pendingQuestion {
                    questionCard(question, receivesFocus: approvals.isEmpty)
                }
            }
            .padding(.horizontal, DSSpacing.m)
            composer()
            if showsKeyHints {
                ReplyKeyHints(
                    context: hintContext,
                    allowsImagePaste: viewModel.agentRef != .builtin(.cursor)
                )
                .padding(.horizontal, DSSpacing.m + DSSpacing.s)
                .padding(.top, -DSSpacing.s)
                .padding(.bottom, DSSpacing.s)
            }
        }
    }

    private var hintContext: ReplyKeyHints.Context {
        if !viewModel.replyApprovals.isEmpty { return isCardFocused ? .approvalCard : .approvalPending }
        if pendingQuestion != nil { return isQuestionFocused ? .questionCard : .questionPending }
        return .composer
    }

    private struct PendingQuestion {
        let itemId: String
        let requestId: String
        let questions: [ChatUserQuestion]
        let timestamp: Date
    }

    /// 返答エリアに質問が出ているか（入力欄の案内と ■ に使う）。
    static func hasPendingQuestion(in transcript: [ChatItem]) -> Bool {
        transcript.contains { item in
            guard case .userQuestion(_, _, let questions, _, .pending, _) = item else { return false }
            return !ChatSessionViewModel.isToolPermissionQuestion(questions)
        }
    }

    /// 返答エリアに出す質問（ツールの使用許可は承認カード側）。最初の 1 件だけ。
    private var pendingQuestion: PendingQuestion? {
        for item in viewModel.transcript {
            guard case .userQuestion(let id, let requestId, let questions, _, .pending, let timestamp) = item,
                  !ChatSessionViewModel.isToolPermissionQuestion(questions)
            else { continue }
            return PendingQuestion(itemId: id, requestId: requestId, questions: questions, timestamp: timestamp)
        }
        return nil
    }

    private func questionCard(_ question: PendingQuestion, receivesFocus: Bool) -> some View {
        UserQuestionCell(
            itemId: question.itemId,
            requestId: question.requestId,
            questions: question.questions,
            answers: nil,
            state: .pending,
            timestamp: question.timestamp,
            onRespond: { requestId, answers in
                await viewModel.respondToUserQuestion(requestId: requestId, answers: answers)
            },
            onDismiss: {
                Task {
                    // Codex の質問なら先に wire を決着させる。Claude の質問は従来どおり直接中断する。
                    if !(await viewModel.declineUserQuestion(requestId: question.requestId)) {
                        await viewModel.turnInterrupt()
                    }
                }
            },
            placement: .replyArea,
            focusRequest: receivesFocus ? viewModel.replyCardFocusRequest : 0,
            onReturnToComposer: { viewModel.returnFocusToComposer() },
            onFocusChange: { isQuestionFocused = $0 }
        )
        .id(question.itemId)
    }
}

/// 送信に失敗したときの通知（05 R9）。下書きは入力欄に戻してある。
private struct SendFailureNotice: View {
    let failure: ChatSessionViewModel.SendFailure
    let onRetry: () -> Void
    let onDismiss: () -> Void

    /// 淡い赤の面に本文色の文字・右に再送（PhloxReply.dc.html の failed）。
    /// ponytail: モックに無い × は、下書きを戻さなかった通知を消す手段が他に無いので残す。
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DSColor.attentionMark(.error))
            Group {
                if failure.restoredDraft {
                    Text("送信できませんでした（\(failure.reason)）。下書きを入力欄に戻しました。")
                } else {
                    Text("送信できませんでした（\(failure.reason)）。")
                }
            }
                .font(.system(size: 12.5))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if failure.restoredDraft {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Text("再送")
                        Text(verbatim: "↩").font(.system(size: 10.5)).foregroundStyle(DSColor.textTertiary)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DSColor.controlBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.textPrimary)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
            }
            .buttonStyle(HoverableIconButtonStyle())
            .foregroundStyle(DSColor.textSecondary)
            .accessibilityLabel(Text("通知を閉じる"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DSColor.attentionMark(.error), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// 入力欄の下のキーの案内（05）。いま効くキーだけを出す。
struct ReplyKeyHints: View {
    enum Context: Equatable {
        case composer
        case approvalPending
        case approvalCard
        case questionPending
        case questionCard
    }

    let context: Context
    let allowsImagePaste: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                item
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(DSColor.textTertiary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var items: [Text] {
        switch context {
        case .composer:
            var items = [Text("↩ 送信"), Text("⇧↩ 改行"), Text("⌘Z 取り消し")]
            if allowsImagePaste { items.append(Text("⌘V 画像も貼り付け")) }
            return items
        case .approvalPending:
            return [Text("⌥⌘↩ 許可"), Text("⌥⌘⌫ 拒否"), Text("Tab で承認カードへ移動すると 1 キーで返せる")]
        case .approvalCard:
            return [Text("Y 許可"), Text("S このセッション中は許可"), Text("N 拒否"), Text("Esc キャンセル"), Text("Tab 入力欄へ戻る")]
        case .questionPending:
            return [Text("Tab で質問カードへ移動"), Text("1–9 選択"), Text("⌘↩ 回答を送信"), Text("Esc 閉じる")]
        case .questionCard:
            return [Text("1–9 選択"), Text("⌘↩ 回答を送信"), Text("Esc 閉じる")]
        }
    }
}
