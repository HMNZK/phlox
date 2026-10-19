import SwiftUI
import DesignSystemIOS
import PhloxCore

struct SessionDetailSubAgentCard: View {
    let text: String

    var body: some View {
        let presentation = SessionDetailTranscriptPresentation.subAgent(from: text)
        DSChatCodeCard {
            SessionDetailTranscriptCardHeader(
                label: "サブエージェント",
                summary: presentation.taskName,
                badges: [SessionDetailTranscriptBadge(
                    id: "status",
                    text: presentation.status.label,
                    color: presentation.status == .running ? IOSColor.text.secondary : IOSColor.text.tertiary
                )],
                isExpanded: false,
                allowsDisclosure: false,
                onToggle: {}
            )
        } content: {
            EmptyView()
        }
        .accessibilityIdentifier("SessionDetailSubAgentCard")
    }
}

struct SessionDetailAnsweredQuestionCard: View {
    let questions: [UserQuestionItem]
    let answers: [String: [String]]?
    let state: UserQuestionState
    let isExpanded: Bool
    let onToggle: () -> Void

    private var headline: String {
        guard let first = questions.first?.header, !first.isEmpty else { return "質問" }
        return questions.count > 1 ? "\(first) ほか \(questions.count - 1) 問" : first
    }

    @ViewBuilder
    var body: some View {
        if let presentation = SessionDetailTranscriptPresentation.settledQuestion(state: state) {
            DSChatCodeCard(showsDivider: isExpanded) {
                SessionDetailTranscriptCardHeader(
                    label: "質問",
                    summary: headline,
                    badges: [SessionDetailTranscriptBadge(
                        id: "state",
                        text: presentation.statusLabel,
                        color: presentation.isAnswered ? IOSColor.status.success : IOSColor.text.tertiary
                    )],
                    isExpanded: isExpanded,
                    allowsDisclosure: true,
                    onToggle: onToggle
                )
            } content: {
                DSDisclosureContent(isExpanded: isExpanded) {
                    VStack(alignment: .leading, spacing: DSSpacing.m) {
                        ForEach(questions, id: \.question) { question in
                            let details = SessionDetailTranscriptPresentation.settledQuestionDetails(
                                for: question,
                                state: state,
                                answers: answers
                            )
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text(question.header)
                                    .font(DSFont.iosCaption2.weight(.medium))
                                    .foregroundStyle(IOSColor.text.secondary)
                                    .textCase(.uppercase)
                                Text(question.question)
                                    .font(DSFont.subheadline)
                                    .foregroundStyle(IOSColor.text.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(details.indices, id: \.self) { index in
                                    switch details[index] {
                                    case .option(let label, let description):
                                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                            Text(label)
                                                .font(DSFont.subheadline)
                                                .foregroundStyle(IOSColor.text.primary)
                                            if let description {
                                                Text(description)
                                                    .font(DSFont.iosCaption2)
                                                    .foregroundStyle(IOSColor.text.secondary)
                                            }
                                        }
                                    case .input(let value):
                                        Text("入力: \(value)")
                                            .font(DSFont.iosCaption2)
                                            .foregroundStyle(IOSColor.text.secondary)
                                    case .expired:
                                        Text("回答は送られませんでした")
                                            .font(DSFont.iosCaption2)
                                            .foregroundStyle(IOSColor.text.tertiary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DSSpacing.m)
                }
            }
            .accessibilityIdentifier("SessionDetailAnsweredQuestionCard")
        }
    }
}

struct SessionDetailErrorCard: View {
    let message: String
    @ScaledMetric(relativeTo: .footnote) private var lineSpacing = DSSpacing.xs

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(DSFont.sessionDetailTechnical)
                .foregroundStyle(IOSColor.status.error)
                .accessibilityHidden(true)
            Text(message)
                .font(DSFont.sessionDetailTechnical)
                .lineSpacing(lineSpacing)
                .foregroundStyle(IOSColor.status.error)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            IOSColor.status.errorBackground,
            in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("エラー、\(message)")
        .accessibilityIdentifier("SessionDetailErrorCard")
    }
}
