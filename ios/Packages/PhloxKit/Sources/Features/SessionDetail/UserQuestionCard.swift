import SwiftUI
import DesignSystemIOS
import PhloxCore

struct UserQuestionCard: View {
    let requestId: String
    let questions: [UserQuestionItem]
    let answers: [String: [String]]?
    let state: UserQuestionState
    let usesInputBarForFreeText: Bool
    let onSubmit: (String, [String: [String]]) async -> Bool

    @State private var form: UserQuestionFormState
    @FocusState private var focusedQuestion: String?
    @State private var isSubmitting = false

    init(
        requestId: String,
        questions: [UserQuestionItem],
        answers: [String: [String]]?,
        state: UserQuestionState,
        usesInputBarForFreeText: Bool = false,
        onSubmit: @escaping (String, [String: [String]]) async -> Bool
    ) {
        self.requestId = requestId
        self.questions = questions
        self.answers = answers
        self.state = state
        self.usesInputBarForFreeText = usesInputBarForFreeText
        self.onSubmit = onSubmit
        _form = State(initialValue: UserQuestionFormState(questions: questions))
    }

    private var isInteractive: Bool { state == .pending && !isSubmitting }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                if state == .pending {
                    Text(UserQuestionFormState.title(for: questions))
                        .font(DSFont.footnote.weight(.semibold))
                        .foregroundStyle(IOSColor.status.question)
                }
                ForEach(Array(questions.enumerated()), id: \.element.question) { index, question in
                    if index > 0 { Rectangle().fill(IOSColor.bg.separator).frame(height: 1) }
                    questionBlock(question, number: index + 1)
                }
                if state == .pending && !usesInputBarForFreeText {
                    VStack(spacing: DSSpacing.s) {
                        DSButton(
                            "回答を送信",
                            variant: .primary,
                            isLoading: isSubmitting,
                            accessibilityIdentifier: "UserQuestionCard.submit"
                        ) {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                        if form.unansweredCount > 0 {
                            Text("あと \(form.unansweredCount) 問に答えると送信できます")
                                .font(DSFont.caption)
                                .foregroundStyle(DSColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                } else if state != .pending {
                    statusCaption
                }
            }
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(.card)
            .opacity(state == .expired ? 0.7 : 1)
        }
        .onAppear(perform: seedFromAnswers)
    }

    private var statusCaption: some View {
        Text(state == .answered ? "回答済み" : "期限切れ")
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textSecondary)
    }

    private var canSubmit: Bool {
        isInteractive && form.canSubmit
    }

    @ViewBuilder
    private func questionBlock(_ question: UserQuestionItem, number: Int) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            HStack(spacing: DSSpacing.s) {
                Text("\(number). \(question.header.uppercased())")
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textSecondary)
                Text(question.multiSelect ? "いくつでも" : "1 つ選ぶ")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, DSSpacing.s)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(DSColor.fillSubtle, in: Capsule())
            }
            Text(question.question)
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(question.options, id: \.label) { option in
                optionButton(question: question, option: option)
            }

            if question.options.isEmpty {
                Text("選択肢のない質問です。下の入力欄に書いて送信してください。")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isInteractive && !usesInputBarForFreeText {
                    freeTextField(question, placeholder: "回答を入力", label: nil)
                }
            } else if isInteractive {
                freeTextField(
                    question,
                    placeholder: "選択肢以外で答える",
                    label: "自由入力（入力すると選択は外れます）"
                )
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

    private func freeTextField(
        _ question: UserQuestionItem,
        placeholder: String,
        label: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let label {
                Text(label)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            TextField(
                placeholder,
                text: freeTextBinding(for: question.question),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .font(DSFont.subheadline)
            .lineLimit(1...4)
            .focused($focusedQuestion, equals: question.question)
            .accessibilityIdentifier("UserQuestionCard.freeText.\(question.question)")
        }
    }

    private func optionButton(question: UserQuestionItem, option: UserQuestionOption) -> some View {
        let selected = isSelected(question: question, label: option.label)
        let symbol = if question.multiSelect {
            selected ? "checkmark.square.fill" : "square"
        } else {
            selected ? "largecircle.fill.circle" : "circle"
        }
        return Button {
            toggle(question: question, label: option.label)
        } label: {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                Image(systemName: symbol)
                    .foregroundStyle(selected ? IOSColor.text.primary : IOSColor.text.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(DSFont.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(DSColor.textPrimary)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: DSTouch.minSize, alignment: .leading)
            .contentShape(Rectangle())
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
        focusedQuestion = nil
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

    private func submit() async {
        guard canSubmit, !isSubmitting, let answers = form.answers else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        _ = await onSubmit(requestId, answers)
    }
}
