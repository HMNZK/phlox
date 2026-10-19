import AgentDomain
import DesignSystemIOS
import PhloxCore
import SwiftUI

/// 新規チャットの作成画面。画面を開くたびに見出しを選び、入力欄へフォーカスする。
public struct NewChatView: View {
    @Environment(\.usageViewModel) private var usageViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var greeting: String
    let viewModel: NewChatViewModel
    let fixedGreeting: String?
    let focusOnAppear: Bool
    let onCreated: (Session, SessionDetailRecovery?) -> Void

    public init(
        viewModel: NewChatViewModel,
        fixedGreeting: String? = nil,
        focusOnAppear: Bool = true,
        onCreated: @escaping (Session, SessionDetailRecovery?) -> Void
    ) {
        self.viewModel = viewModel
        self.fixedGreeting = fixedGreeting
        self.focusOnAppear = focusOnAppear
        self.onCreated = onCreated
        _greeting = State(initialValue: fixedGreeting ?? NewChatViewModel.greetings.randomElement() ?? NewChatViewModel.greetings[0])
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.showsSubmittedConversation {
                        createdConversation
                        Spacer(minLength: 12)
                    } else {
                        Spacer(minLength: 12)
                        greetingView
                            .padding(.bottom, 20)
                        Spacer(minLength: 12)
                    }

                    if viewModel.progressStage == .idle {
                        suggestionRow
                            .padding(.bottom, 10)
                    }

                    if let presentation = viewModel.creationErrorPresentation {
                        catalogError(presentation)
                            .padding(.bottom, 8)
                    } else if let message = viewModel.projectValidationMessage {
                        errorLine(message)
                            .padding(.bottom, 8)
                    }

                    inputBar
                    if let usageViewModel, usageViewModel.shouldShowRow {
                        UsageRingRow(viewModel: usageViewModel)
                            .padding(.horizontal, DSSpacing.xl)
                            .padding(.top, DSSpacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.top, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(IOSColor.bg.base.ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: modelPickerBinding) {
            NewChatModelPickerSheet(
                sections: viewModel.modelSections,
                selectedEntryID: viewModel.selectedEntryID,
                defaultEntryIDs: viewModel.defaultEntryIDs,
                onSelect: viewModel.selectModel(entryID:),
                onDismiss: { viewModel.isModelPickerPresented = false }
            )
            .presentationBackground(IOSColor.bg.sheet)
            .presentationCornerRadius(32)
            .presentationDetents([.height(680), .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await viewModel.load()
            await usageViewModel?.load()
        }
        .onChange(of: fixedGreeting) { _, value in
            guard let value else { return }
            greeting = value
        }
        .accessibilityIdentifier("newChat.screen")
    }

    private var greetingView: some View {
        Text(verbatim: greeting)
            .font(DSFont.displayDot(for: dynamicTypeSize))
            .tracking(-0.1)
            .foregroundStyle(DSColor.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("newChat.greeting")
    }

    private var createdConversation: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if let text = viewModel.submittedText {
                HStack {
                    Spacer(minLength: 36)
                    Text(verbatim: text)
                        .font(DSFont.body)
                        .foregroundStyle(IOSColor.text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            if viewModel.isSending {
                creationProgressCard
            }
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.top, 24)
        .accessibilityIdentifier("newChat.progress")
    }

    private var creationProgressCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.progressStage == .creating ? "セッションを作成しています…" : "作成しました")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.progressStage == .creating ? DSColor.textPrimary : IOSColor.status.success)
                Spacer()
                if viewModel.progressStage == .creating {
                    ProgressView()
                        .tint(IOSColor.text.tertiary)
                }
                Text("\(viewModel.selectedProject?.name ?? "プロジェクト") · \(viewModel.selectedModelDisplayName)")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
                    .lineLimit(1)
            }.frame(minHeight: 36)

            HStack {
                Text(readinessTitle)
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.progressStage == .creating ? IOSColor.text.secondary : DSColor.textPrimary)
                Spacer(minLength: 8)
                if viewModel.progressStage == .waiting {
                    ProgressView()
                        .tint(IOSColor.text.tertiary)
                    Text("\(viewModel.readyWaitSeconds) 秒")
                        .font(DSFont.subheadline)
                        .foregroundStyle(IOSColor.text.secondary)
                        .fixedSize()
                } else if viewModel.progressStage == .sending {
                    Image(systemName: "checkmark")
                        .foregroundStyle(IOSColor.status.success)
                        .accessibilityHidden(true)
                } else {
                    Text("作成できたら")
                        .font(DSFont.subheadline)
                        .foregroundStyle(IOSColor.text.secondary)
                }
            }.frame(minHeight: 36)

            HStack {
                Text(viewModel.progressStage == .sending ? "指示を送っています…" : "指示を送る")
                    .font(DSFont.subheadline)
                    .foregroundStyle(viewModel.progressStage == .sending ? DSColor.textPrimary : IOSColor.text.secondary)
                Spacer()
                if viewModel.progressStage == .sending {
                    ProgressView()
                        .tint(IOSColor.text.tertiary)
                } else {
                    Text("準備ができたら")
                        .font(DSFont.subheadline)
                        .foregroundStyle(IOSColor.text.secondary)
                }
            }.frame(minHeight: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(IOSColor.bg.separator, lineWidth: 1)
        }
    }

    private var readinessTitle: String {
        switch viewModel.progressStage {
        case .creating: "準備を待つ"
        case .waiting: "準備ができるのを待っています…"
        case .sending: "準備ができました"
        case .idle: "準備を待つ"
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) {
                ForEach(Array(NewChatViewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        viewModel.appendSuggestion(index)
                    } label: {
                        Text(verbatim: suggestion.title)
                            .font(DSFont.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(IOSColor.text.primary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 40)
                            .background(IOSColor.bg.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(IOSColor.bg.separator, lineWidth: 1))
                            .contentShape(Rectangle().inset(by: -2))
                    }
                    .buttonStyle(DSPressFeedbackStyle())
                    .accessibilityLabel("提案: \(suggestion.title)。入力欄に追記します")
                    .accessibilityIdentifier("newChat.suggestion.\(index + 1)")
                }
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.zero, for: .scrollContent)
        .accessibilityElement(children: .contain)
    }

    private var inputBar: some View {
        let settings = DSInputBarSettings(
            agentName: viewModel.selectedAgent.displayName,
            effortOptions: viewModel.selectedEffortOptions.map {
                DSInputBarSettingOption(value: $0.value, displayName: $0.displayName)
            },
            selectedEffort: viewModel.selectedEffort,
            permissionOptions: viewModel.selectedPermissionOptions.map {
                DSInputBarSettingOption(value: $0.value, displayName: $0.displayName)
            },
            selectedPermission: viewModel.selectedPermission,
            planMode: viewModel.planMode,
            planModeAvailable: viewModel.planModeAvailable,
            onSelectEffort: viewModel.selectEffort,
            onSelectPermission: viewModel.selectPermission,
            onSelectPlanMode: viewModel.selectPlanMode
        )
        let projectOptions = viewModel.projects.map {
            DSInputBarProjectOption(
                id: $0.id,
                name: $0.name,
                isLastUsed: $0.id == viewModel.lastUsedProjectID
            )
        }
        return VStack(spacing: DSSpacing.s) {
            DSInputBar(
                text: inputTextBinding,
                cursorUTF16: inputCursorBinding,
                isLoading: viewModel.isSending,
                attachmentStrip: viewModel.attachmentItems.map {
                    DSAttachmentStripItem(id: $0.id, number: $0.number, previewData: $0.previewData)
                },
                attachmentError: viewModel.attachmentError,
                maxAttachments: ImageAttachmentLimits.maxCount,
                onAddAttachments: { results in Task { await viewModel.addAttachmentLoadResults(results) } },
                onRemoveAttachment: viewModel.removeAttachment(at:),
                onAttachmentLimitReached: viewModel.attachmentLimitReached,
                mode: .newChat,
                model: (viewModel.selectedAgent, viewModel.selectedModelDisplayName),
                onSelectModel: { viewModel.isModelPickerPresented = true },
                settings: settings,
                projectName: viewModel.selectedProject?.name,
                projectOptions: projectOptions,
                selectedProjectID: viewModel.selectedProjectID,
                onSelectProjectID: { viewModel.selectProject(id: $0) },
                focusOnAppear: focusOnAppear,
                focusRequest: viewModel.focusRequest
            ) {
                Task { await viewModel.send(onCreated: onCreated) }
            }
            .disabled(!viewModel.canEditDraft)
            .onChange(of: viewModel.inputText) { oldValue, newValue in
                viewModel.syncAttachmentsWithTextEdit(oldText: oldValue, newText: newValue)
            }
        }
    }

    private var inputTextBinding: Binding<String> {
        Binding(get: { viewModel.inputText }, set: {
            guard viewModel.canEditDraft else { return }
            viewModel.inputText = $0
        })
    }

    private var inputCursorBinding: Binding<Int> {
        Binding(get: { viewModel.inputCursorUTF16 }, set: {
            guard viewModel.canEditDraft else { return }
            viewModel.inputCursorUTF16 = $0
        })
    }

    private var modelPickerBinding: Binding<Bool> {
        Binding(get: { viewModel.isModelPickerPresented }, set: { viewModel.isModelPickerPresented = $0 })
    }

    private func errorLine(_ message: String) -> some View {
        Text(verbatim: message)
            .font(DSFont.inputBar(.error, for: dynamicTypeSize).weight(.semibold))
            .foregroundStyle(IOSColor.status.error)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }

    private func catalogError(_ presentation: ErrorPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(presentation.title)
                .font(DSFont.inputBar(.error, for: dynamicTypeSize).weight(.semibold))
                .foregroundStyle(presentation.isNeutral ? IOSColor.text.primary : IOSColor.status.error)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.cause)
                .font(DSFont.iosCaption2)
                .foregroundStyle(IOSColor.text.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.nextStep.isEmpty {
                Text(presentation.nextStep)
                    .font(DSFont.iosCaption2)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let technicalDetail = presentation.technicalDetail {
                Text("（\(technicalDetail)）")
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct NewChatModelPickerSheet: View {
    let sections: [NewChatAgentModelSection]
    let selectedEntryID: String?
    let defaultEntryIDs: Set<String>
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    var body: some View {
        ModelSelectionSheet(
            title: "モデル",
            searchText: $searchText,
            explanation: "モデルを選ぶと、エージェントもそのモデルのものに切り替わります",
            onDismiss: onDismiss
        ) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        DSAgentBrandIcon(kind: section.kind, size: 16)
                        Text(section.kind.displayName)
                            .font(DSFont.subheadline.weight(.semibold))
                            .foregroundStyle(IOSColor.text.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if section.isUnavailable {
                            Text("取得できません")
                                .font(DSFont.body)
                                .foregroundStyle(IOSColor.text.secondary)
                                .accessibilityAddTraits(.isStaticText)
                        } else if filteredModels(in: section).isEmpty {
                            Text(searchText.isEmpty ? "モデルがありません" : "該当するモデルがありません")
                                .font(DSFont.body)
                                .foregroundStyle(IOSColor.text.secondary)
                        } else {
                            ForEach(filteredModels(in: section)) { model in
                                modelButton(kind: section.kind, model: model)
                                if model.id != filteredModels(in: section).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private func filteredModels(in section: NewChatAgentModelSection) -> [SessionModelOption] {
        let models = section.models ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private func modelButton(kind: AgentKind, model: SessionModelOption) -> some View {
        let entryID = "\(kind.rawValue)::\(model.id)"
        let selected = entryID == selectedEntryID
        let isDefault = defaultEntryIDs.contains(entryID)
        return Button { onSelect(entryID) } label: {
            HStack(spacing: DSSpacing.s) {
                Text(verbatim: model.displayName)
                    .font(DSFont.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(IOSColor.text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.s)
                if isDefault {
                    Text("既定")
                        .font(DSFont.iosCaption2.weight(.medium))
                        .foregroundStyle(IOSColor.text.secondary)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, 2)
                        .background(DSColor.fillSubtle, in: Capsule())
                }
                Image(systemName: "checkmark")
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(IOSColor.accent)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DSTouch.minSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityLabel("\(model.displayName)\(isDefault ? "、既定" : "")\(selected ? "、選択中" : "")")
    }
}
