import SwiftUI
import DesignSystemIOS
import PhloxCore

/// AskUserQuestion の質問カード（SessionDetail 配下で完結。DesignSystemIOS への新規コンポーネント追加はしない）。
struct UserQuestionCard: View {
    let requestId: String
    let questions: [UserQuestionItem]
    let answers: [String: [String]]?
    let state: UserQuestionState
    let onSubmit: (String, [String: [String]]) async -> Bool

    @State private var form: UserQuestionFormState
    @FocusState private var focusedQuestion: String?
    @State private var isSubmitting = false

    init(
        requestId: String,
        questions: [UserQuestionItem],
        answers: [String: [String]]?,
        state: UserQuestionState,
        onSubmit: @escaping (String, [String: [String]]) async -> Bool
    ) {
        self.requestId = requestId
        self.questions = questions
        self.answers = answers
        self.state = state
        self.onSubmit = onSubmit
        _form = State(initialValue: UserQuestionFormState(questions: questions))
    }

    private var isInteractive: Bool { state == .pending && !isSubmitting }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            ForEach(questions, id: \.question) { question in
                questionBlock(question)
            }
            if state == .pending {
                DSButton(
                    "回答する",
                    variant: .primary,
                    isLoading: isSubmitting,
                    accessibilityIdentifier: "UserQuestionCard.submit"
                ) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
            } else {
                statusCaption
            }
        }
        .padding(DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.campSurfaceEmphasis, in: cardShape)
        .overlay(cardShape.strokeBorder(borderColor, lineWidth: 1))
        .opacity(state == .expired ? 0.7 : 1)
        .onAppear(perform: seedFromAnswers)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
    }

    private var borderColor: Color {
        switch state {
        case .pending:
            DSColor.statusAwaitingApproval.opacity(0.35)
        case .answered:
            DSColor.statusRunning.opacity(0.35)
        case .expired:
            DSColor.border
        }
    }

    private var statusCaption: some View {
        Text(state == .answered ? "回答済み" : "期限切れ")
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textSecondary)
    }

    private var canSubmit: Bool {
        guard isInteractive else { return false }
        return form.canSubmit
    }

    @ViewBuilder
    private func questionBlock(_ question: UserQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(question.header)
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textSecondary)
                .textCase(.uppercase)
            Text(question.question)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(question.options, id: \.label) { option in
                optionButton(question: question, option: option)
            }

            if isInteractive {
                TextField(
                    "自由入力",
                    text: freeTextBinding(for: question.question),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .font(DSFont.subheadline)
                .lineLimit(1...4)
                .focused($focusedQuestion, equals: question.question)
                .accessibilityIdentifier("UserQuestionCard.freeText.\(question.question)")
            } else if let custom = customAnswerText(for: question), !isKnownOption(custom, in: question) {
                Text("入力: \(custom)")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .onChange(of: focusedQuestion) { _, focusedQuestion in
            guard let focusedQuestion else { return }
            form.freeTextDidFocus(question: focusedQuestion)
        }
    }

    private func optionButton(question: UserQuestionItem, option: UserQuestionOption) -> some View {
        let selected = isSelected(question: question, label: option.label)
        return Button {
            toggle(question: question, label: option.label)
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DSColor.accent : DSColor.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(DSFont.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(selected ? DSColor.fillSubtle : DSColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .strokeBorder(selected ? DSColor.accent.opacity(0.5) : DSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("UserQuestionCard.option.\(option.label)")
    }

    private func freeTextBinding(for question: String) -> Binding<String> {
        Binding(
            get: { form.freeText[question] ?? "" },
            set: { form.setFreeText(question: question, text: $0) }
        )
    }

    private func isSelected(question: UserQuestionItem, label: String) -> Bool {
        (form.selections[question.question] ?? []).contains(label)
    }

    private func toggle(question: UserQuestionItem, label: String) {
        guard isInteractive else { return }
        if question.multiSelect {
            form.toggleMulti(question: question.question, label: label)
        } else {
            form.selectSingle(question: question.question, label: label)
        }
    }

    private func seedFromAnswers() {
        guard let answers else { return }
        form.seed(from: answers)
    }

    private func customAnswerText(for question: UserQuestionItem) -> String? {
        answers?[question.question]?.first
    }

    private func isKnownOption(_ value: String, in question: UserQuestionItem) -> Bool {
        question.options.contains(where: { $0.label == value })
    }

    private func buildAnswers() -> [String: [String]] {
        form.answers ?? [:]
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        _ = await onSubmit(requestId, buildAnswers())
    }
}
