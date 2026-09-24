import SwiftUI
import AppKit
import AgentDomain
import DesignSystem

/// シングルビューでサブエージェント別チャットを表示する右ペイン。
///
/// Bug2/3/4 対応: 以前は `.overlay` で本文の上に浮かせていたが、現在は `ChatSessionView` の
/// HStack 水平分割の右カラムとして配置され、幅は親が `.frame(width:)` で与える（本ビューは
/// 与えられたフレームを満たすだけ）。左端の境界線・リサイズ掴みしろは親側が担う。
/// ヘッダー高さは本体の `ChatSessionHeader.height` に揃え、メイン側ヘッダーと罫線を揃える。
struct SubAgentDrawerView: View {
    let subAgent: SubAgentRef
    let transcript: [ChatItem]
    let agentDescriptor: AgentDescriptor
    let canSendFollowUp: Bool
    let onSendFollowUp: (String) -> Void
    let onClose: () -> Void

    @State private var draft = ""
    @State private var editorHeight: CGFloat = ComposerHeightBounds.single.min
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            transcriptBody
            followUpComposer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.panelBackground)
        .accessibilityIdentifier("SubAgentDrawerView")
    }

    /// PhloxChat.dc.html: 高さ 56・説明 13/600 と等幅 11.5 の「種類 · 状態」、右に「メインへ戻る」と ✕。
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subAgent.description.isEmpty ? subAgent.subagentType : subAgent.description)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(subAgent.subagentType) · \(statusLabel)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("メインへ戻る", action: onClose)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textSecondary)
                .help("メインチャットを表示")
                .accessibilityIdentifier("SubAgentDrawer.backToMain")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HoverableIconButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("閉じる（Esc）")
            .accessibilityLabel(Text("閉じる"))
            .accessibilityIdentifier("SubAgentDrawer.close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        // 本体のセッションヘッダ（56pt）と同じ高さにして下の罫線を一直線にする（Bug4・04 C3）。
        .frame(height: ChatSessionHeader.height)
        .frame(maxWidth: .infinity)
    }

    private var statusLabel: Text {
        switch subAgent.status {
        case .running: Text("実行中")
        case .completed: Text("完了")
        case .failed: Text("失敗")
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if transcript.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("まだ表示できる出力がありません")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.chatTextSecondary)
                Button("メインへ戻る", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.accentInk)
                    .help("メインチャットを表示")
            }
            .padding(DSSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let lastItemID = transcript.last?.id
            let blocks = ChatTranscriptGrouping.blocks(from: transcript)
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    ForEach(blocks) { block in
                        transcriptBlock(block, lastItemID: lastItemID)
                            .id(block.id)
                    }
                    if SubAgentDrawerPresentation.showsThinkingIndicator(status: subAgent.status) {
                        ThinkingIndicatorCell(
                            descriptor: agentDescriptor,
                            state: SubAgentDrawerPresentation.activityState(
                                transcript: transcript,
                                status: subAgent.status
                            )
                        )
                        .id("subagent-thinking")
                    }
                }
                .padding(.horizontal, DSSpacing.l)
                .padding(.vertical, DSSpacing.m)
            }
        }
    }

    private var followUpComposer: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Divider().overlay(DSColor.separator)
            HStack(alignment: .bottom, spacing: DSSpacing.s) {
                ZStack(alignment: .topLeading) {
                    IMESafeTextView(
                        text: $draft,
                        isComposing: $isComposing,
                        measuredHeight: $editorHeight,
                        minHeight: ComposerHeightBounds.single.min,
                        maxHeight: ComposerHeightBounds.single.max,
                        onSubmit: submitFollowUp
                    )
                    .frame(
                        minHeight: ComposerHeightBounds.single.min,
                        idealHeight: editorHeight,
                        maxHeight: ComposerHeightBounds.single.max
                    )
                    .accessibilityIdentifier("SubAgentDrawer.input")

                    if ComposerPlaceholderVisibility.shouldShowPlaceholder(text: draft, isComposing: isComposing) {
                        Text("サブエージェントに追加の指示")
                            .font(ComposerPlaceholderMetrics.placeholderFont)
                            .foregroundStyle(DSColor.chatTextSecondary)
                            .padding(.horizontal, ComposerPlaceholderMetrics.textInsets.width)
                            .padding(.vertical, ComposerPlaceholderMetrics.textInsets.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: editorHeight)

                SubAgentDrawerSendButton(
                    canSubmit: canSendFollowUp && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: submitFollowUp
                )
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
        }
        .background(DSColor.chatCard)
    }

    private func submitFollowUp() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendFollowUp, !trimmed.isEmpty else { return }
        draft = ""
        onSendFollowUp(trimmed)
    }

    @ViewBuilder
    private func transcriptBlock(_ block: ChatTranscriptBlock, lastItemID: String?) -> some View {
        switch block {
        case .single(let item):
            ChatItemView(
                item: item,
                isRunningCommand: SubAgentDrawerPresentation.isRunningCommand(
                    item: item,
                    lastItemID: lastItemID,
                    status: subAgent.status
                ),
                agentDescriptor: agentDescriptor
            )
        case .commandGroup(_, let items):
            CommandGroupCell(
                items: items,
                lastTranscriptID: lastItemID,
                isTurnRunning: subAgent.status == .running
            )
        }
    }
}

private struct SubAgentDrawerSendButton: View {
    let canSubmit: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSubmit ? DSColor.chatBackground : DSColor.chatTextSecondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .fill(canSubmit ? DSColor.chatAccent : Color.clear)
                    if isHovering && canSubmit {
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .disabled(!canSubmit)
        .accessibilityIdentifier("SubAgentDrawer.sendButton")
        .help("送信")
    }
}
