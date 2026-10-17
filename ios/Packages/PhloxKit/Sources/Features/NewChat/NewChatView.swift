import SwiftUI
import AgentDomain
import DesignSystemIOS
import PhloxCore

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
        VStack(spacing: 0) {
            if viewModel.hasCreatedSession {
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

            if let message = viewModel.creationError ?? viewModel.projectValidationMessage {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
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
            .padding(.horizontal, 16)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .presentationBackground(.clear)
            .presentationCornerRadius(32)
            .presentationDetents([.height(680)])
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
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("newChat.greeting")
    }

    private var createdConversation: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if let text = viewModel.submittedText {
                Text(verbatim: text)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.l)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
            }
            creationProgressCard
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.top, 24)
        .accessibilityIdentifier("newChat.progress")
    }

    private var creationProgressCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("作成しました")
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(IOSColor.status.success)
                Spacer()
                Text("\(viewModel.selectedProject?.name ?? "プロジェクト") · \(viewModel.selectedModelDisplayName)")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text("準備ができるのを待っています…")
                    .font(DSFont.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer(minLength: 8)
                ProgressView()
                    .tint(IOSColor.text.tertiary)
                Text("\(viewModel.readyWaitSeconds) 秒")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize()
            }

            HStack {
                Text("指示を送る")
                    .font(DSFont.body)
                    .foregroundStyle(IOSColor.text.secondary)
                Spacer()
                Text("準備ができたら")
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
                .strokeBorder(IOSColor.bg.separator, lineWidth: 1)
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
                            .font(DSFont.body)
                            .lineLimit(1)
                        .foregroundStyle(IOSColor.text.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: DSTouch.minSize)
                        .background(DSColor.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(IOSColor.bg.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("提案: \(suggestion.title)。入力欄に追記します")
                    .accessibilityIdentifier("newChat.suggestion.\(index + 1)")
                }
            }
            .padding(.horizontal, DSSpacing.s)
        }
        .contentMargins(.zero, for: .scrollContent)
        .padding(.horizontal, DSSpacing.m)
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
                onAddAttachments: { candidates in Task { await viewModel.addAttachments(candidates) } },
                onRemoveAttachment: viewModel.removeAttachment(at:),
                onAttachmentLimitReached: viewModel.attachmentLimitReached,
                onAttachmentLoadFailure: viewModel.attachmentLoadFailed,
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
            .onChange(of: viewModel.inputText) { oldValue, newValue in
                viewModel.syncAttachmentsWithTextEdit(oldText: oldValue, newText: newValue)
            }
        }
    }

    private var inputTextBinding: Binding<String> {
        Binding(get: { viewModel.inputText }, set: { viewModel.inputText = $0 })
    }

    private var inputCursorBinding: Binding<Int> {
        Binding(get: { viewModel.inputCursorUTF16 }, set: { viewModel.inputCursorUTF16 = $0 })
    }

    private var modelPickerBinding: Binding<Bool> {
        Binding(get: { viewModel.isModelPickerPresented }, set: { viewModel.isModelPickerPresented = $0 })
    }

    private func errorLine(_ message: String) -> some View {
        Text(verbatim: message)
            .font(DSFont.captionStrong)
            .foregroundStyle(IOSColor.status.error)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.m)
            .accessibilityAddTraits(.isStaticText)
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
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: DSSpacing.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(IOSColor.text.secondary)
                    TextField("絞り込み", text: $searchText)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                        .accessibilityLabel("モデルを絞り込む")
                }
                .font(DSFont.body)
                .padding(.horizontal, DSSpacing.m)
                .frame(height: 40)
                .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, DSSpacing.l)
                .padding(.top, DSSpacing.s)

                List {
                    ForEach(sections) { section in
                        Section {
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
                                        .listRowInsets(EdgeInsets(
                                            top: 0,
                                            leading: DSSpacing.m,
                                            bottom: 0,
                                            trailing: DSSpacing.m
                                        ))
                                }
                            }
                        } header: {
                            HStack(spacing: DSSpacing.s) {
                                DSAgentBrandIcon(kind: section.kind, size: 18)
                                Text(section.kind.displayName)
                            }
                            .textCase(nil)
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .scrollContentBackground(.hidden)
            }
            .background(IOSColor.bg.base)
            .navigationTitle("モデル")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onDismiss)
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(IOSColor.text.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("モデルを選ぶと、エージェントもそのモデルのものに切り替わります")
                    .font(DSFont.caption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.top, DSSpacing.s)
                    .padding(.bottom, DSSpacing.m)
                    .background(.regularMaterial)
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
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.s)
                if isDefault {
                    Text("既定")
                        .font(DSFont.captionStrong)
                        .foregroundStyle(IOSColor.text.secondary)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, 2)
                        .background(DSColor.fillSubtle, in: Capsule())
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(DSFont.body.weight(.semibold))
                        .foregroundStyle(IOSColor.accent)
                }
            }
            .frame(minHeight: DSTouch.minSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(DSColor.surface)
        .accessibilityLabel("\(model.displayName)\(isDefault ? "、既定" : "")\(selected ? "、選択中" : "")")
    }
}
