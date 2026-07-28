import SwiftUI
import DesignSystem
import StructuredChatKit

/// AskUserQuestion の質問カード（task-2）。
struct UserQuestionCell: View {
    let itemId: String
    let requestId: String
    let questions: [ChatUserQuestion]
    let answers: [String: [String]]?
    let state: ChatUserQuestionState
    let timestamp: Date
    var onRespond: ((String, [String: [String]]) async -> Bool)?
    /// 回答せずにカードを閉じる。中身はターンの中断（Esc と同じ）で、
    /// カードは `.turnInterrupted` 経由で「期限切れ」になる。
    var onDismiss: (() -> Void)?

    @State private var form: UserQuestionFormModel
    @State private var isSubmitting = false
    @FocusState private var focusedFreeTextQuestion: String?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    init(
        itemId: String,
        requestId: String,
        questions: [ChatUserQuestion],
        answers: [String: [String]]?,
        state: ChatUserQuestionState,
        timestamp: Date,
        onRespond: ((String, [String: [String]]) async -> Bool)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.itemId = itemId
        self.requestId = requestId
        self.questions = questions
        self.answers = answers
        self.state = state
        self.timestamp = timestamp
        self.onRespond = onRespond
        self.onDismiss = onDismiss
        _form = State(initialValue: UserQuestionFormModel(questions: questions))
    }

    private var isInteractive: Bool {
        state == .pending && onRespond != nil
    }

    /// 閉じられるのは「未回答のカード」で「閉じる操作が配線されている」ときだけ。
    /// 回答済み・期限切れのカードには出さない（押しても何も起きないボタンを見せない）。
    private var canDismiss: Bool {
        state == .pending && onDismiss != nil
    }

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if state == .expired || canDismiss {
                HStack(spacing: DSSpacing.s) {
                    if state == .expired {
                        Label("期限切れ", systemImage: "clock.badge.exclamationmark")
                            .font(ChatScaledFont.captionStrong(scale: scale))
                            .foregroundStyle(DSColor.chatTextSecondary)
                    }
                    Spacer(minLength: 0)
                    if canDismiss {
                        dismissButton
                    }
                }
            }

            ForEach(questions, id: \.question) { question in
                questionBlock(question, scale: scale)
            }

            if isInteractive {
                Button("送信") {
                    submitForm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!form.canSubmit || isSubmitting)
                .accessibilityIdentifier("UserQuestionCell.submit.\(itemId)")
            }
        }
        .padding(DSSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .fill(DSColor.fillSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(stateBorderColor, lineWidth: 1)
        )
        .frame(maxWidth: 720, alignment: .leading)
        .accessibilityIdentifier("UserQuestionCell.\(itemId)")
    }

    /// 回答せずに別の指示を出したいときのための閉じるボタン。
    /// グリッドタイルのヘッダー（`PaneLayoutView`）と同じ手触りに揃える。
    private var dismissButton: some View {
        Button(action: { onDismiss?() }) {
            Image(systemName: "xmark")
                .imageScale(.small)
                .foregroundStyle(DSColor.chatTextSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("回答せずに閉じる（ターンを中断する）")
        .accessibilityLabel("回答せずに閉じる")
        .accessibilityIdentifier("UserQuestionCell.dismiss.\(itemId)")
    }

    private var stateBorderColor: Color {
        switch state {
        case .pending:
            DSColor.chatTextSecondary.opacity(0.25)
        case .answered:
            DSColor.chatSuccess.opacity(0.45)
        case .expired:
            DSColor.statusError.opacity(0.35)
        }
    }

    @ViewBuilder
    private func questionBlock(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(question.header)
                .font(ChatScaledFont.captionStrong(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .padding(.horizontal, DSSpacing.s)
                .padding(.vertical, 2)
                .background(DSColor.fillSubtle, in: Capsule())

            Text(question.question)
                .font(ChatScaledFont.body(scale: scale).weight(.semibold))
                .foregroundStyle(DSColor.chatTextPrimary)

            if state == .answered, let selected = answers?[question.question], !selected.isEmpty {
                answeredLabels(selected, question: question, scale: scale)
            } else if state == .expired {
                expiredQuestionBody(question, scale: scale)
            } else {
                pendingQuestionBody(question, scale: scale)
            }
        }
    }

    @ViewBuilder
    private func answeredLabels(
        _ selected: [String],
        question: ChatUserQuestion,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(selected, id: \.self) { label in
                optionLabel(
                    label: label,
                    description: question.options.first { $0.label == label }?.description,
                    scale: scale,
                    isSelected: true,
                    isEnabled: false
                ) {}
            }
        }
    }

    @ViewBuilder
    private func expiredQuestionBody(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(question.options, id: \.label) { option in
                optionLabel(
                    label: option.label,
                    description: option.description,
                    scale: scale,
                    isSelected: false,
                    isEnabled: false
                ) {}
            }
        }
    }

    @ViewBuilder
    private func pendingQuestionBody(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            if !question.options.isEmpty {
                if question.multiSelect {
                    multiSelectOptions(question, scale: scale)
                } else {
                    singleSelectOptions(question, scale: scale)
                }
            }

            freeTextInput(question, scale: scale)
        }
    }

    @ViewBuilder
    private func singleSelectOptions(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        let selected = form.selections[question.question, default: []]
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(question.options, id: \.label) { option in
                optionLabel(
                    label: option.label,
                    description: option.description,
                    scale: scale,
                    isSelected: selected == [option.label],
                    isEnabled: isInteractive && !isSubmitting
                ) {
                    guard isInteractive, !isSubmitting else { return }
                    form.selectSingle(question: question.question, label: option.label)
                }
            }
        }
    }

    @ViewBuilder
    private func multiSelectOptions(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        let selections = form.selections[question.question, default: []]
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ForEach(question.options, id: \.label) { option in
                optionLabel(
                    label: option.label,
                    description: option.description,
                    scale: scale,
                    isSelected: selections.contains(option.label),
                    isEnabled: isInteractive && !isSubmitting
                ) {
                    guard isInteractive, !isSubmitting else { return }
                    form.toggleMulti(question: question.question, label: option.label)
                }
            }
        }
    }

    @ViewBuilder
    private func freeTextInput(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        if isInteractive {
            TextField("自由入力", text: binding(for: question.question), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(ChatScaledFont.body(scale: scale))
                .lineLimit(1...4)
                .focused($focusedFreeTextQuestion, equals: question.question)
                .onChange(of: focusedFreeTextQuestion) { _, focusedQuestion in
                    guard focusedQuestion == question.question else { return }
                    form.freeTextDidFocus(question: question.question)
                }
                .accessibilityIdentifier("UserQuestionCell.freeText.\(question.question)")
                .disabled(isSubmitting)
        }
    }

    private func binding(for questionText: String) -> Binding<String> {
        Binding(
            get: { form.freeText[questionText, default: ""] },
            set: { newValue in
                if focusedFreeTextQuestion == questionText {
                    form.freeTextDidChangeWhileFocused(question: questionText, text: newValue)
                } else {
                    form.setFreeText(question: questionText, text: newValue)
                }
            }
        )
    }

    @ViewBuilder
    private func optionLabel(
        label: String,
        description: String?,
        scale: CGFloat,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DSColor.chatSuccess)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(ChatScaledFont.body(scale: scale))
                        .foregroundStyle(DSColor.chatTextPrimary)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(ChatScaledFont.caption(scale: scale))
                            .foregroundStyle(DSColor.chatTextSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                    .fill(isSelected ? DSColor.chatSuccess.opacity(0.12) : DSColor.fillSubtle)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func submitForm() {
        guard isInteractive, !isSubmitting else { return }
        guard let payload = form.payload else { return }
        guard let onRespond else { return }
        isSubmitting = true
        Task {
            _ = await onRespond(requestId, payload)
            await MainActor.run {
                isSubmitting = false
            }
        }
    }
}
