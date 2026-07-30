import Foundation
import SwiftUI
import ChatRenderKit
import DesignSystemIOS
import PhloxCore

struct SessionDetailCommandCardData: Equatable {
    let toolLabel: String
    let commandBody: String
    let highlightedCommand: AttributedString
    let copyText: String
    let output: String

    init(command: String?, output: String) {
        let tool = ChatCommandToolLabel.derive(command: command)
        toolLabel = tool.label
        commandBody = tool.body
        highlightedCommand = CodeHighlighter.shell(tool.body)
        copyText = ChatMessageCopyText.copyText(
            for: .command(id: "", command: command, output: output)
        ) ?? ""
        self.output = output
    }
}

struct SessionDetailCommandCard: View {
    let data: SessionDetailCommandCardData
    let isExpanded: Bool
    let onToggle: () -> Void

    init(
        command: String?,
        output: String,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            data: SessionDetailCommandCardData(command: command, output: output),
            isExpanded: isExpanded,
            onToggle: onToggle
        )
    }

    init(
        data: SessionDetailCommandCardData,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.data = data
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    var body: some View {
        DSChatCodeCard {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(data.toolLabel)
                        .font(DSFont.captionStrong)
                        .foregroundStyle(DSColor.chatTextSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(DSColor.chatTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } content: {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                commandLine

                if isExpanded, !data.output.isEmpty {
                    Text(data.output)
                        .font(DSFont.campMonoCaption)
                        .tracking(-0.5)
                        .foregroundStyle(DSColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.top, DSSpacing.s)
            .padding(.bottom, DSSpacing.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("SessionDetailCommandCard")
    }

    @ViewBuilder
    private var commandLine: some View {
        if data.commandBody.isEmpty {
            Text("$")
                .font(DSFont.campMonoCaption)
                .foregroundStyle(DSColor.chatTextPrimary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("$ ")
                Text(data.highlightedCommand)
            }
            .font(DSFont.campMonoCaption)
            .foregroundStyle(DSColor.chatTextPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
