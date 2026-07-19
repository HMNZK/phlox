import SwiftUI
import AgentDomain
import DesignSystem

/// シングルビューでサブエージェント別チャットを表示する右ペイン。
///
/// Bug2/3/4 対応: 以前は `.overlay` で本文の上に浮かせていたが、現在は `ChatSessionView` の
/// HStack 水平分割の右カラムとして配置され、幅は親が `.frame(width:)` で与える（本ビューは
/// 与えられたフレームを満たすだけ）。左端の境界線・リサイズ掴みしろは親側が担う。
/// ヘッダー高さは `SubAgentSplitLayout.headerHeight` に固定し、メイン側ヘッダーと罫線を揃える。
struct SubAgentDrawerView: View {
    let subAgent: SubAgentRef
    let transcript: [ChatItem]
    let agentDescriptor: AgentDescriptor
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DSColor.separator)
            transcriptBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.chatBackground)
        .accessibilityIdentifier("SubAgentDrawerView")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpacing.s) {
            statusIcon
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(subAgent.description.isEmpty ? "Sub-agent" : subAgent.description)
                    .font(DSFont.sectionHeader)
                    .foregroundStyle(DSColor.chatTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(subAgent.subagentType) · \(subAgent.status.rawValue)")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.chatTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.s, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(HoverableIconButtonStyle())
            .help("閉じる")
            .accessibilityIdentifier("SubAgentDrawer.close")
        }
        .padding(.horizontal, DSSpacing.m)
        // メイン側ヘッダーと同一高さに固定して下の罫線を一直線にする（Bug4）。
        .frame(height: SubAgentSplitLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background(DSColor.chatCard)
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
                    .foregroundStyle(DSColor.chatAccent)
                    .help("メインチャットを表示")
            }
            .padding(DSSpacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let lastItemID = transcript.last?.id
            let blocks = ChatTranscriptGrouping.blocks(from: transcript)
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    Button {
                        onClose()
                    } label: {
                        Label("メインへ戻る", systemImage: "text.bubble")
                            .font(DSFont.captionStrong)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DSColor.chatAccent)
                    .help("メインチャットを表示")

                    ForEach(blocks) { block in
                        transcriptBlock(block, lastItemID: lastItemID)
                            .id(block.id)
                    }
                    if SubAgentDrawerPresentation.showsThinkingIndicator(status: subAgent.status) {
                        ThinkingIndicatorCell(
                            descriptor: agentDescriptor,
                            reasoningPreview: SubAgentDrawerPresentation.reasoningPreview(
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

    @ViewBuilder
    private var statusIcon: some View {
        switch subAgent.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DSColor.chatSuccess)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DSColor.statusError)
        }
    }
}
