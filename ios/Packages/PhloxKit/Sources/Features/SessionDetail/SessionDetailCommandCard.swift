import SwiftUI
import ChatRenderKit
import DesignSystemIOS
import PhloxCore

struct SessionDetailCommandCardData: Equatable {
    let toolLabel: String
    let commandBody: String
    let summary: String
    let copyText: String
    let output: String

    init(command: String?, output: String) {
        let tool = ChatCommandToolLabel.derive(command: command)
        toolLabel = tool.label == "Bash" ? "コマンド" : tool.label
        commandBody = tool.body
        summary = tool.label == "Bash" ? "$ \(tool.body)" : tool.body
        copyText = ChatMessageCopyText.copyText(
            for: .command(id: "", command: command, output: output)
        ) ?? ""
        self.output = output
    }
}

struct SessionDetailCommandCard: View {
    let data: SessionDetailCommandCardData
    let isExpanded: Bool
    let isRunning: Bool
    let onToggle: () -> Void

    init(
        command: String?,
        output: String,
        isExpanded: Bool,
        isRunning: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.data = SessionDetailCommandCardData(command: command, output: output)
        self.isExpanded = isExpanded
        self.isRunning = isRunning
        self.onToggle = onToggle
    }

    init(
        data: SessionDetailCommandCardData,
        isExpanded: Bool,
        isRunning: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.data = data
        self.isExpanded = isExpanded
        self.isRunning = isRunning
        self.onToggle = onToggle
    }

    var body: some View {
        DSChatCodeCard(isRunning: isRunning, showsDivider: isExpanded) {
            SessionDetailTranscriptCardHeader(
                label: data.toolLabel,
                summary: data.summary,
                badges: headerBadges,
                isExpanded: isExpanded,
                allowsDisclosure: true,
                onToggle: onToggle
            )
        } content: {
            DSDisclosureContent(isExpanded: isExpanded) {
                SessionDetailCommandOutputView(
                    output: data.output,
                    copyText: data.copyText.isEmpty ? nil : data.copyText
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("SessionDetailCommandCard")
    }

    private var headerBadges: [SessionDetailTranscriptBadge] {
        if isRunning {
            return [SessionDetailTranscriptBadge(id: "running", text: "実行中", color: IOSColor.text.primary)]
        }
        guard let exitCode = SessionDetailTranscriptPresentation.exitCode(in: data.output) else { return [] }
        return [SessionDetailTranscriptBadge(
            id: "exit",
            text: "exit \(exitCode)",
            color: exitCode == 0 ? IOSColor.text.tertiary : IOSColor.status.error
        )]
    }
}
