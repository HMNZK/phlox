import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

/// 会話画面の下端（05）。上から 送信失敗の通知 → 承認カード → 質問カード → 入力欄 → キーの案内。
/// 承認と質問は会話の中に流さず、入力欄の直上に出す。カードが出ても入力欄のフォーカスは動かさない。
struct ChatReplyArea<Composer: View>: View {
    @Bindable var viewModel: ChatSessionViewModel
    var showsKeyHints = true
    let onRetrySend: () -> Void
    @ViewBuilder let composer: () -> Composer

    @State private var isCardFocused = false

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
                        onFocusChange: { isCardFocused = $0 }
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
        if pendingQuestion != nil { return .questionPending }
        return .composer
    }

    private struct PendingQuestion {
        let itemId: String
        let requestId: String
        let questions: [ChatUserQuestion]
        let timestamp: Date
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
            onReturnToComposer: { viewModel.returnFocusToComposer() }
        )
        .id(question.itemId)
    }
}

/// 送信に失敗したときの通知（05 R9）。下書きは入力欄に戻してある。
private struct SendFailureNotice: View {
    let failure: ChatSessionViewModel.SendFailure
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.attentionMark(.error))
            Group {
                if failure.restoredDraft {
                    Text("送信できませんでした（\(failure.reason)）。下書きを入力欄に戻しました。")
                } else {
                    Text("送信できませんでした（\(failure.reason)）。")
                }
            }
                .font(.system(size: 12))
                .foregroundStyle(DSColor.attentionInk(.error))
                .lineLimit(2)
            Spacer(minLength: DSSpacing.s)
            if failure.restoredDraft {
            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Text("再送")
                    Text(verbatim: "↩").opacity(0.7)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(DSColor.chatBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(DSColor.border, lineWidth: 1)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(DSColor.attentionTint(.error), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
    }

    let context: Context
    let allowsImagePaste: Bool

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                item
            }
        }
        .font(.system(size: 11))
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
        }
    }
}
