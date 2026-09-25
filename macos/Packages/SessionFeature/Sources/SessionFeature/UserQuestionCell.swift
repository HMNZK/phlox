import SwiftUI
import DesignSystem
import StructuredChatKit

enum UserQuestionAnswerDisplay {
    static let secretMask = String(repeating: "●", count: 8)

    /// 回答済みカードで描画するラベルを生成する。
    /// 秘密の回答は表示時だけ同一の固定長マスクへ置き換え、送信値は変更しない。
    static func labels(for answers: [String], isSecret: Bool) -> [String] {
        isSecret ? Array(repeating: secretMask, count: answers.count) : answers
    }

    /// ツールの使用許可（Claude）の回答は「許可 / 拒否」で見せる（送信値は Allow / Deny のまま）。
    static func permissionLabel(_ label: String, question: ChatUserQuestion, locale: Locale) -> String {
        guard question.permission != nil else { return label }
        switch label {
        case "Allow": return AppLocalizedString.string("許可", locale: locale)
        case ChatSessionViewModel.allowForSessionAnswer:
            return AppLocalizedString.string("このセッション中は許可", locale: locale)
        case "Deny": return AppLocalizedString.string("拒否", locale: locale)
        default: return label
        }
    }
}

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
    /// 未回答のカードは返答エリア（入力欄の直上）に、回答済み・期限切れは会話の中に 1 行で残す（05 R7〜R7d）。
    var placement: Placement = .replyArea

    enum Placement {
        case replyArea
        case transcript
    }

    @State private var form: UserQuestionFormModel
    @State private var isSubmitting = false
    @FocusState private var focusedFreeTextQuestion: String?
    @FocusState private var isCardFocused: Bool
    @Environment(\.locale) private var locale
    /// 入力欄の Tab でカードへ移る要求（値の変化だけを見る）。
    var focusRequest = 0
    /// カードの Tab で入力欄へ戻る。
    var onReturnToComposer: (() -> Void)?
    /// カードのフォーカスが変わったとき（入力欄の下のキーの案内を切り替える）。
    var onFocusChange: ((Bool) -> Void)?
    /// 秘密の入力を一時的に見せる（「表示」ボタン。05 R7c）。
    @State private var revealsSecret = false
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
        onDismiss: (() -> Void)? = nil,
        placement: Placement = .replyArea,
        focusRequest: Int = 0,
        onReturnToComposer: (() -> Void)? = nil,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.itemId = itemId
        self.requestId = requestId
        self.questions = questions
        self.answers = answers
        self.state = state
        self.timestamp = timestamp
        self.onRespond = onRespond
        self.onDismiss = onDismiss
        self.placement = placement
        self.focusRequest = focusRequest
        self.onReturnToComposer = onReturnToComposer
        self.onFocusChange = onFocusChange
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
        if placement == .transcript, state != .pending {
            settledRow(scale: scale)
        } else {
            card(scale: scale)
        }
    }

    // MARK: - 返答エリアのカード（R7〜R7c）

    private func card(scale: CGFloat) -> some View {
        // 角丸 10・余白 11/13/12・間隔 9（PhloxReply.dc.html の qStyle。フォーカスは承認カードと同じ外の 3pt の輪）。
        VStack(alignment: .leading, spacing: 9) {
            ForEach(questions, id: \.question) { question in
                questionBlock(question, scale: scale)
            }
            if isInteractive {
                footerRow(scale: scale)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 12, trailing: 13))
        .background(DSColor.attentionTint(.question), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DSColor.attentionMark(.question), lineWidth: 1)
        )
        .background {
            if isCardFocused {
                // カードの面は半透明なので、塗りではなく外側の 3pt の輪だけにする。
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(DSColor.focusRing, lineWidth: 3)
                    .padding(-3)
            }
        }
        .focusable(isInteractive)
        .focusEffectDisabled()
        .focused($isCardFocused)
        // 1〜9 で選ぶ・⌘↩ で送る・Esc で閉じる（カードにフォーカスがあるときだけ。13 Review のキー表）。
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let digit = Int(press.characters), digit >= 1 else { return .ignored }
            selectOption(number: digit)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            submitForm()
            return .handled
        }
        .onKeyPress(.escape) {
            guard canDismiss else { return .ignored }
            onDismiss?()
            onReturnToComposer?()
            return .handled
        }
        .onKeyPress(.tab) {
            onReturnToComposer?()
            return .handled
        }
        .onChange(of: focusRequest) { _, _ in isCardFocused = true }
        .onChange(of: isCardFocused) { _, focused in onFocusChange?(focused) }
        .onDisappear { onFocusChange?(false) }
        .accessibilityIdentifier("UserQuestionCell.\(itemId)")
    }

    private func footerRow(scale: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(keyHint)
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textTertiary)
            Spacer(minLength: 8)
            if canDismiss {
                dismissButton
            }
            Button {
                submitForm()
            } label: {
                HStack(spacing: 6) {
                    Text("回答を送信")
                    Text(verbatim: "⌘↩").opacity(0.85).font(.system(size: 10.5))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DSColor.accentFill.opacity(form.canSubmit && !isSubmitting ? 1 : 0.5),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!form.canSubmit || isSubmitting)
            .accessibilityIdentifier("UserQuestionCell.submit.\(itemId)")
        }
    }

    private var keyHint: LocalizedStringKey {
        let optionCount = questions.count == 1 ? min(questions[0].options.count, 9) : 0
        let multi = questions.first?.multiSelect == true
        if optionCount > 0 {
            return multi
                ? "1–\(optionCount) で切り替え · ⌘↩ 送信"
                : "1–\(optionCount) で選択 · ⌘↩ 送信 · Esc 閉じる"
        }
        return "⌘↩ 送信 · Esc 閉じる"
    }

    /// 番号で選ぶ（質問が 1 つのときだけ）。複数選べるときは切り替え。
    private func selectOption(number: Int) {
        guard isInteractive, !isSubmitting, questions.count == 1 else { return }
        let question = questions[0]
        guard number <= question.options.count else { return }
        let label = question.options[number - 1].label
        if question.multiSelect {
            form.toggleMulti(question: question.answerKey, label: label)
        } else {
            form.selectSingle(question: question.answerKey, label: label)
        }
    }

    // MARK: - 会話に残る 1 行（R7d）

    private func settledRow(scale: CGFloat) -> some View {
        // 余白 8/12・角丸 9・12.5。期限切れは文字をすべて淡く（PhloxReply.dc.html の answered）。
        let isExpired = state == .expired
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state == .answered ? "回答済み" : "期限切れ")
                .font(.system(size: 12.5 * scale, weight: .semibold))
                .foregroundStyle(isExpired ? DSColor.textTertiary : DSColor.chatTextPrimary)
            Text(verbatim: settledSummary)
                .font(.system(size: 12.5 * scale))
                .foregroundStyle(isExpired ? DSColor.textTertiary : DSColor.chatTextSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(settledSummary)
            Spacer(minLength: DSSpacing.s)
            Text(timestamp, format: .dateTime.hour().minute())
                .font(.system(size: 11 * scale))
                .foregroundStyle(DSColor.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(state == .answered ? DSColor.fillSubtle : Color.clear)
        )
        .overlay {
            if isExpired {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(DSColor.fieldBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("UserQuestionCell.\(itemId)")
    }

    /// 回答済み「見出し: 回答」、期限切れ「「質問」— 回答は送られませんでした」。秘密の回答は伏せ字。
    private var settledSummary: String {
        if state == .answered {
            return questions.map { question in
                let selected = answers?[question.answerKey] ?? []
                let labels = UserQuestionAnswerDisplay.labels(for: selected, isSecret: question.isSecret)
                    .map { UserQuestionAnswerDisplay.permissionLabel($0, question: question, locale: locale) }
                return "\(question.header): \(labels.joined(separator: ", "))"
            }.joined(separator: " · ")
        }
        let first = questions.first?.question ?? ""
        return "「\(first)」— " + AppLocalizedString.string("回答は送られませんでした", locale: locale)
    }

    /// 回答せずに別の指示を出したいときのための閉じるボタン。
    /// グリッドタイルのヘッダー（`PaneLayoutView`）と同じ手触りに揃える。
    private var dismissButton: some View {
        Button(action: { onDismiss?() }) {
            Text("閉じる")
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("回答せずに閉じる（ターンを中断する）")
        .accessibilityLabel("回答せずに閉じる")
        .accessibilityIdentifier("UserQuestionCell.dismiss.\(itemId)")
    }

    @ViewBuilder
    private func questionBlock(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.square.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DSColor.attentionMark(.question))
                Text("質問待ち · \(question.header)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DSColor.attentionInk(.question))
                Spacer(minLength: DSSpacing.s)
                Text(question.isSecret ? "秘密の入力"
                     : question.options.isEmpty ? "自由入力"
                     : question.multiSelect ? "複数選べる" : "1 つ選ぶ")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
            }

            Text(question.question)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DSColor.chatTextPrimary)

            if state == .answered, let selected = answers?[question.answerKey], !selected.isEmpty {
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
        let displayLabels = UserQuestionAnswerDisplay.labels(
            for: selected,
            isSecret: question.isSecret
        )
        VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
            ForEach(selected.indices, id: \.self) { index in
                let answer = selected[index]
                optionLabel(
                    label: displayLabels[index],
                    description: question.options.first { $0.label == answer }?.description,
                    scale: scale,
                    isSelected: true,
                    isEnabled: false
                ) {}
            }
        }
    }

    @ViewBuilder
    private func expiredQuestionBody(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
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
        VStack(alignment: .leading, spacing: 9) {
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
        let selected = form.selections[question.answerKey, default: []]
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.element.label) { offset, option in
                optionLabel(
                    label: option.label,
                    description: option.description,
                    scale: scale,
                    isSelected: selected == [option.label],
                    isEnabled: isInteractive && !isSubmitting,
                    number: questions.count == 1 && offset < 9 ? offset + 1 : nil,
                    style: .radio
                ) {
                    guard isInteractive, !isSubmitting else { return }
                    form.selectSingle(question: question.answerKey, label: option.label)
                }
            }
        }
    }

    @ViewBuilder
    private func multiSelectOptions(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        let selections = form.selections[question.answerKey, default: []]
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(question.options.enumerated()), id: \.element.label) { offset, option in
                optionLabel(
                    label: option.label,
                    description: option.description,
                    scale: scale,
                    isSelected: selections.contains(option.label),
                    isEnabled: isInteractive && !isSubmitting,
                    number: questions.count == 1 && offset < 9 ? offset + 1 : nil,
                    style: .checkbox
                ) {
                    guard isInteractive, !isSubmitting else { return }
                    form.toggleMulti(question: question.answerKey, label: option.label)
                }
            }
        }
    }

    /// 自由入力欄（高さ 30・角丸 7・入力欄の面と縁）と秘密の入力欄（高さ 32・等幅 14・「表示」・説明）。05 R7 / R7c。
    @ViewBuilder
    private func freeTextInput(_ question: ChatUserQuestion, scale: CGFloat) -> some View {
        if isInteractive {
            let isFocused = focusedFreeTextQuestion == question.answerKey
            if question.isSecret {
                HStack(spacing: 8) {
                    configuredFreeTextInput(
                        Group {
                            if revealsSecret {
                                TextField("秘密の値", text: binding(for: question.answerKey))
                            } else {
                                SecureField("秘密の値", text: binding(for: question.answerKey))
                            }
                        }
                        .font(.system(size: 14 * scale, design: .monospaced))
                        .tracking(2),
                        question: question
                    )
                    Button(revealsSecret ? "隠す" : "表示") { revealsSecret.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("UserQuestionCell.revealSecret.\(question.answerKey)")
                }
                .padding(.horizontal, 10)
                .frame(height: 32 * scale)
                .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isFocused ? DSColor.accent : DSColor.fieldBorder, lineWidth: isFocused ? 2 : 1)
                )
                Text("入力値は伏せ字で表示し、会話の履歴と書き出しには残しません。")
                    .font(.system(size: 11.5 * scale))
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                configuredFreeTextInput(
                    TextField("その他（自由に入力）", text: binding(for: question.answerKey), axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 12.5 * scale)),
                    question: question
                )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: 30 * scale)
                    .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isFocused ? DSColor.accent : DSColor.fieldBorder, lineWidth: 1)
                    )
            }
        }
    }

    /// 自由入力欄の共通設定（フォーカスの追跡と、フォーカス時の選択肢の解除）。
    private func configuredFreeTextInput<Content: View>(_ content: Content, question: ChatUserQuestion) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($focusedFreeTextQuestion, equals: question.answerKey)
            .onChange(of: focusedFreeTextQuestion) { _, focusedQuestion in
                guard focusedQuestion == question.answerKey else { return }
                form.freeTextDidFocus(question: question.answerKey)
            }
            .accessibilityIdentifier("UserQuestionCell.freeText.\(question.answerKey)")
            .disabled(isSubmitting)
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

    enum OptionStyle {
        case plain
        case radio
        case checkbox
    }

    @ViewBuilder
    private func optionLabel(
        label: String,
        description: String?,
        scale: CGFloat,
        isSelected: Bool,
        isEnabled: Bool,
        number: Int? = nil,
        style: OptionStyle = .plain,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DSSpacing.s) {
                switch style {
                case .radio:
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? DSColor.attentionMark(.question) : DSColor.textTertiary)
                case .checkbox:
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isSelected ? DSColor.attentionMark(.question) : DSColor.textTertiary)
                case .plain:
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DSColor.chatSuccess)
                    }
                }
                VStack(alignment: .leading, spacing: TranscriptTypography.metadataGap) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(DSColor.chatTextPrimary)
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(DSColor.chatTextSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DSColor.chatBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? DSColor.attentionMark(.question) : DSColor.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func submitForm() {
        guard isInteractive, !isSubmitting else { return }
        guard let payload = form.payload else { return }
        guard let onRespond else { return }
        isSubmitting = true
        // カードから送ったら入力欄へ戻す（カードが消えるとキーの行き先が無くなる）。
        let returnsFocus = isCardFocused || focusedFreeTextQuestion != nil
        Task {
            let sent = await onRespond(requestId, payload)
            await MainActor.run {
                isSubmitting = false
                if sent, returnsFocus { onReturnToComposer?() }
            }
        }
    }
}
