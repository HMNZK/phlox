import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

private struct NewChatSendButtonInitiallyFocusedKey: EnvironmentKey {
    static let defaultValue = false
}
private struct NewChatModelMenuInitiallyOpenKey: EnvironmentKey {
    static let defaultValue = false
}
private struct NewChatSendValidationInitiallyShownKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var newChatSendButtonInitiallyFocused: Bool {
        get { self[NewChatSendButtonInitiallyFocusedKey.self] }
        set { self[NewChatSendButtonInitiallyFocusedKey.self] = newValue }
    }
    var newChatModelMenuInitiallyOpen: Bool {
        get { self[NewChatModelMenuInitiallyOpenKey.self] }
        set { self[NewChatModelMenuInitiallyOpenKey.self] = newValue }
    }
    /// 画面外の描画で、送ろうとした後の検証メッセージを出した状態を撮る。
    var newChatSendValidationInitiallyShown: Bool {
        get { self[NewChatSendValidationInitiallyShownKey.self] }
        set { self[NewChatSendValidationInitiallyShownKey.self] = newValue }
    }
}

private struct NewChatSendButtonStyle: ButtonStyle {
    let canSend: Bool

    func makeBody(configuration: Configuration) -> some View {
        SendButtonStyleBody(configuration: configuration, canSend: canSend)
    }

    private struct SendButtonStyleBody: View {
        let configuration: ButtonStyle.Configuration
        let canSend: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(fill, in: Circle())
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && canSend ? 0.995 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovering = $0 && canSend }
        }

        private var fill: Color {
            guard canSend else { return DSColor.sendDisabledFill }
            if configuration.isPressed { return DSColor.sendPressedFill }
            if isHovering { return DSColor.sendHoverFill }
            return DSColor.accentFill
        }
    }
}

struct NewChatView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var draft: NewChatDraft
    let project: Project?
    let onLaunchFailure: (AgentRef, Error) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.newChatSendButtonInitiallyFocused) private var newChatSendButtonInitiallyFocused
    @Environment(\.newChatSendValidationInitiallyShown) private var newChatSendValidationInitiallyShown
    /// 送ろうとして送れなかった後だけ理由を出す（要件 E7）。原因が解消したら下ろす。
    @State private var showsSendValidation = false
    @Environment(\.newChatModelMenuInitiallyOpen) private var newChatModelMenuInitiallyOpen
    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }
    @State private var greeting = NewChatGreetings.random()
    @State private var modelSearch = ""
    @FocusState private var sendButtonFocused: Bool
    @FocusState private var harnessPickerFocused: Bool
    @State private var focusToken = 0
    @State private var isLaunching = false
    @State private var isGitRepository: Bool?
    @State private var spawnGuard: SpawnGuard?
    @State private var historyModel = NewChatHistoryPopoverModel()
    @State private var historyPopoverPresented = false
    @State private var pendingResumeHistoryID: String?

    private var detectedHarnessIDs: Set<String> {
        Set(viewModel.availableAgentKinds.map(\.rawValue))
    }
    private var modelSections: [NewChatModelMenuSection] {
        NewChatModelMenuSection.make(availableHarnessIDs: detectedHarnessIDs)
    }
    private var selectedKind: AgentKind? { draft.agentRef.builtinKind }
    private var selectedSection: NewChatModelMenuSection? { modelSections.first { $0.kind == selectedKind } }
    private var selectedModelOption: ControlModelOption? {
        selectedSection?.models.first { $0.id == draft.settings.selectedModel }
    }
    private var selectedModelTitle: String {
        selectedModelOption?.displayName ?? draft.settings.selectedModel ?? localized("モデル")
    }
    var harnessAccessibility: NewChatAccessibilityCopy {
        .init(role: localized("ハーネスとモデル"), value: "\(selectedSection?.name ?? "") \(selectedModelTitle)")
    }
    var effortAccessibility: NewChatAccessibilityCopy {
        .init(role: localized("推論の深さ"), value: effortTitle(draft.settings.selectedEffort ?? ""))
    }
    var permissionAccessibility: NewChatAccessibilityCopy {
        .init(role: localized(selectedKind == .cursor ? "mode" : "権限"), value: selectedPermissionTitle)
    }
    var projectAccessibility: NewChatAccessibilityCopy {
        .init(role: localized("プロジェクト"), value: destinationName ?? localized("未選択"))
    }
    var workspaceAccessibility: NewChatAccessibilityCopy {
        .init(role: localized("作業場所"), value: localized(draft.usesWorktree ? "新しい worktree" : "既存ディレクトリ"))
    }
    private var modelAcceptsImages: Bool {
        switch selectedKind {
        case .claudeCode: true
        case .codex: selectedModelOption?.acceptsImages != false
        case .cursor, nil: false
        }
    }
    private var canSend: Bool {
        draft.canSend(
            projectExists: hasDestination,
            harnessDetected: detectedHarnessIDs.contains(draft.agentRef.id),
            modelAcceptsImages: modelAcceptsImages
        ) && !isLaunching
    }
    private var sendUnavailableReason: String? {
        draft.sendUnavailableReason(
            projectExists: hasDestination,
            harnessDetected: detectedHarnessIDs.contains(draft.agentRef.id),
            modelAcceptsImages: modelAcceptsImages,
            locale: locale,
            bundle: localizationBundle
        )
    }
    private var validationMessage: String? { showsSendValidation ? sendUnavailableReason : nil }
    private var showsProjectError: Bool { validationMessage != nil && !hasDestination }
    /// 送信先のフォルダ。プロジェクトか、送信するまでプロジェクトにしないフォルダ。
    private var destinationDirectory: String? { project?.directoryPath ?? draft.pendingFolderPath }
    private var destinationName: String? {
        project?.name ?? draft.pendingFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
    private var hasDestination: Bool { project.map { selectedProjectExists($0.id) } ?? (draft.pendingFolderPath != nil) }
    private var suggestionDirectory: String? {
        destinationDirectory.map { NewChatSuggestionDirectory.path(projectDirectory: $0, usesWorktree: draft.usesWorktree) }
    }
    private var effortOptions: [ComposerSettingOption] {
        guard let kind = selectedKind else { return [] }
        let available = newChatEffortOptions(for: kind, modelID: draft.settings.selectedModel, languageCode: languageCode, bundle: localizationBundle).map {
            ComposerSettingOption(value: $0.value, title: $0.displayName)
        }
        guard let selected = draft.settings.selectedEffort, !available.contains(where: { $0.value == selected }) else { return available }
        return available + [ComposerSettingOption(value: selected, title: effortTitle(selected))]
    }
    private var permissionOptions: [ComposerModeOption] {
        guard let kind = selectedKind else { return [] }
        return composerModeOptions(for: .builtin(kind), codexProfileIDs: [":danger-full-access", ":workspace", ":read-only"], languageCode: languageCode)
    }
    private var selectedPermissionTitle: String {
        permissionOptions.first(where: {
            draft.settings.isPlanMode == true ? $0.isPlan : !$0.isPlan && $0.value == draft.settings.selectedPermissionProfile
        })?.title
            ?? localized("既定")
    }
    private var historyKey: String? {
        guard let project, draft.agentRef == .builtin(.claudeCode) || draft.agentRef == .builtin(.codex) else { return nil }
        return ([project.id.description, draft.agentRef.id, project.directoryPath] + (project.worktreePaths ?? [])).joined(separator: "\u{1f}")
    }
    private var showsHistoryResumeButton: Bool {
        historyKey != nil && (historyModel.state != .empty || historyPopoverPresented)
    }
    var body: some View {
        GeometryReader { geometry in
            let composerWidth = max(0, min(760, geometry.size.width - 48))
            let compactSettings = composerWidth < DSLayout.newChatCompactSettingsWidthThreshold
            let compactLabels = composerWidth < DSLayout.newChatCompactLabelsWidthThreshold
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Text(verbatim: localized(greeting))
                        .font(NewChatHeadingFont.font)
                        .tracking(-0.1)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                }
                .padding(.bottom, 20)
                composer(width: composerWidth, compactSettings: compactSettings, compactLabels: compactLabels)
                    .padding(.bottom, validationMessage == nil ? 16 : 8)
                    .zIndex(1)
                if let validationMessage {
                    Label { Text(verbatim: validationMessage) } icon: { Image(systemName: "exclamationmark.circle") }
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.attentionInk(.error))
                        .lineLimit(2)
                        .frame(width: composerWidth, alignment: .leading)
                        .padding(.leading, DSSpacing.s)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("newChat.sendUnavailableReason")
                }
                suggestions
                Spacer(minLength: 12)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .onChange(of: sendUnavailableReason) { showsSendValidation = false }
            .onAppear {
                showsSendValidation = newChatSendValidationInitiallyShown
                greeting = NewChatGreetings.random()
                if newChatSendButtonInitiallyFocused {
                    sendButtonFocused = true
                } else {
                    focusToken &+= 1
                }
            }
            .onChange(of: router.newChatFocusToken) { _, _ in
                focusToken &+= 1
            }
            .onChange(of: router.newChatProjectID) { _, id in
                if id != nil { draft.pendingFolderPath = nil }
            }
            .task(id: destinationDirectory) {
                guard let destinationDirectory else { isGitRepository = nil; return }
                isGitRepository = await WorkingTreeService(repositoryRoot: URL(fileURLWithPath: destinationDirectory)).isGitRepository()
            }
            .task(id: historyKey) {
                guard historyKey != nil else { historyModel.reset(); return }
                await loadHistoryEntries()
            }
        }
        .overlay(alignment: .topLeading) {
            if newChatModelMenuInitiallyOpen {
                GeometryReader { geometry in
                    let menuWidth = DSLayout.harnessMenuWidth
                    let menuHeight = DSLayout.harnessMenuHeight
                    let buttonX = max(0, (geometry.size.width - min(geometry.size.width, 760)) / 2 + 75)
                    let menuCenterX = max(menuWidth / 2 + 8, min(buttonX, geometry.size.width - menuWidth / 2 - 8))
                    let menuCenterY = min(geometry.size.height - menuHeight / 2, geometry.size.height * 0.28)
                    modelPickerMenu
                        .frame(width: DSLayout.harnessMenuWidth, height: menuHeight)
                        .position(x: menuCenterX, y: menuCenterY)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func composer(width: CGFloat, compactSettings: Bool, compactLabels: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerDraftInput(
                text: $draft.text,
                attachmentStore: draft.attachments,
                workingDirectory: suggestionDirectory ?? "",
                agentKind: selectedKind ?? .claudeCode,
                placeholder: localized("やりたいことを入力（/ でコマンド）"),
                focusToken: focusToken,
                accessibilityPrefix: "newChat",
                inputAccessibilitySuffix: "messageInput",
                emptyTextHeight: DSLayout.newChatComposerTextHeight,
                onSubmit: { attemptSend() },
                onCycleEffort: cycleEffort,
                onTab: { harnessPickerFocused = true; return true },
                onAcceptSkill: { draft.selectedSkill = $0 }
            )
            .id("\(suggestionDirectory ?? "")#\(draft.agentRef.id)")
            .padding(.leading, DSSpacing.xxs)
            .padding(.trailing, -DSSpacing.xxs)
            .padding(.bottom, DSSpacing.xs)
            .accessibilityIdentifier("newChat.composer")
            HStack(spacing: 0) {
                HStack(spacing: DSSpacing.xxs) {
                    ComposerAttachPlaceholder(
                        text: $draft.text,
                        attachmentStore: draft.attachments,
                        agentRef: draft.agentRef,
                        imageAttachmentsSupported: selectedKind != .cursor,
                        accessibilityIdentifier: "newChat.attachments"
                    )
                    harnessModelPicker(allowsTruncation: compactLabels)
                    if compactSettings {
                        compactSettingsMenu
                    } else {
                        if !effortOptions.isEmpty { effortPicker }
                        permissionPicker
                    }
                }

                Spacer(minLength: DSSpacing.s)

                HStack(spacing: DSSpacing.xxs) {
                    projectPicker(isCompact: compactLabels)
                    workspacePicker(isCompact: compactLabels)
                    Color.clear.frame(width: DSSpacing.chip)
                    sendButton
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .frame(height: DSLayout.newChatComposerControlRowHeight)
            .padding(.leading, DSLayout.newChatComposerLeadingInset)
            .padding(.trailing, DSLayout.newChatComposerTrailingInset)
            .padding(.top, DSLayout.newChatComposerToolbarTopInset)
            .padding(.bottom, DSLayout.newChatComposerToolbarBottomInset)
            .focusSection()
            if draft.usesWorktree {
                HStack(spacing: DSSpacing.xxs) {
                    Spacer(minLength: DSSpacing.s)
                    Text(verbatim: localized("起点"))
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textSecondary)
                    WorktreeStartPointPicker(draft: draft, projectID: project?.id, directory: destinationDirectory)
                }
                .padding(.horizontal, DSLayout.newChatComposerTrailingInset)
                .padding(.bottom, DSLayout.newChatComposerToolbarBottomInset)
            }
        }
        .frame(width: width, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: DSRadius.l, style: .continuous)
            // フォーカス中も枠は変えない（要件 §5.1。2026-10-13 ユーザー指示）。
            shape.fill(DSColor.fieldBackground)
                .overlay(shape.strokeBorder(DSColor.fieldBorder, lineWidth: 1))
        }
        .dsDialog(item: $spawnGuard) { item in
            SpawnGuardSheet(
                spawnGuard: item,
                onCancel: { spawnGuard = nil; pendingResumeHistoryID = nil; focusToken &+= 1 },
                onLaunch: { separates in
                    spawnGuard = nil
                    draft.usesWorktree = separates
                    if let pendingResumeHistoryID {
                        resumeHistory(pendingResumeHistoryID)
                    } else {
                        send()
                    }
                },
                onUseWorktree: { path in
                    spawnGuard = nil
                    draft.usesWorktree = false
                    if let pendingResumeHistoryID {
                        resumeHistory(pendingResumeHistoryID, workingDirectoryOverride: path)
                    } else {
                        send(workingDirectoryOverride: path)
                    }
                }
            )
        }
    }

    private func harnessModelPicker(allowsTruncation: Bool) -> some View {
        ComposerSettingPopover(
            options: modelPickerOptions,
            selectedID: selectedModelMenuID,
            accessibilityLabel: harnessAccessibility.role,
            accessibilityValue: harnessAccessibility.value,
            accessibilityIdentifier: "newChat.harnessModelPicker",
            help: "\(selectedSection?.name ?? "")：\(selectedModelTitle)",
            width: DSLayout.harnessMenuWidth,
            maxHeight: DSLayout.harnessMenuHeight,
            footer: modelPickerFooter,
            searchText: $modelSearch,
            searchAccessibilityIdentifier: "newChat.modelSearch",
            showsFocusRing: true,
            onSelect: { selectModel(id: $0.id) }
        ) { _ in
            ComposerSettingChipLabel(title: selectedModelTitle, harnessKind: selectedKind, allowsTruncation: allowsTruncation)
        }
        .focused($harnessPickerFocused)
    }

    private var modelPickerFooter: String {
        composerModelPickerFooter(languageCode: locale.language.languageCode?.identifier ?? locale.identifier)
    }

    private var modelPickerOptions: [SelectablePopoverOption] {
        modelSections.flatMap { section in
            if section.isDetected {
                return section.models.map { model in
                    SelectablePopoverOption(
                        id: modelSelectionID(model, in: section),
                        value: model.id,
                        title: model.displayName,
                        sectionTitle: section.name,
                        sectionAgent: section.kind,
                        badge: model.id == section.defaultModel ? localized("既定") : nil,
                        isSelected: section.kind == selectedKind && model.id == draft.settings.selectedModel
                    )
                }
            }
            return [SelectablePopoverOption(
                id: "missing:\(section.kind.rawValue)",
                title: localized("未検出"),
                sectionTitle: section.name,
                sectionAgent: section.kind,
                detail: String(format: localized("%@ が見つかりません。インストールすると選べます"), section.name),
                isEnabled: false,
                isSelectable: false
            )]
        }
    }

    private var selectedModelMenuID: String? {
        guard let selectedSection, let selectedModelOption else { return nil }
        return modelSelectionID(selectedModelOption, in: selectedSection)
    }

    private func modelSelectionID(_ model: ControlModelOption, in section: NewChatModelMenuSection) -> String {
        "\(section.kind.rawValue):\(model.id)"
    }

    private var modelPickerMenu: some View {
        SelectablePopover(
            options: modelPickerOptions,
            selectedID: selectedModelMenuID,
            width: DSLayout.harnessMenuWidth,
            maxHeight: DSLayout.harnessMenuHeight,
            footer: modelPickerFooter,
            searchText: $modelSearch,
            accessibilityIdentifier: "newChat.modelMenu",
            onSelect: { selectModel(id: $0.id) }
        )
    }

    private var effortPicker: some View {
        ComposerSettingChip(
            title: effortTitle(draft.settings.selectedEffort ?? effortOptions.first?.value ?? ""),
            options: effortOptions,
            selection: draft.settings.selectedEffort,
            accessibilityIdentifier: "newChat.effortPicker",
            leadingSystemImage: "gauge",
            showsFocusRing: true,
            onSelect: selectEffort
        )
        .accessibilityLabel(Text(verbatim: effortAccessibility.role))
        .accessibilityValue(Text(verbatim: effortAccessibility.value))
    }

    private var permissionPicker: some View {
        ComposerSettingPopover(
            accessibilityLabel: permissionAccessibility.role,
            accessibilityValue: permissionAccessibility.value,
            accessibilityIdentifier: "newChat.permissionPicker",
            showsFocusRing: true
        ) { _ in
            ComposerSettingChipLabel(title: selectedPermissionTitle, systemImage: "shield")
        } content: { dismiss in
            ComposerPopupSurface(width: 340, padding: 10) {
                permissionPanel(onClose: dismiss)
            }
        }
    }

    private var compactSettingsMenu: some View {
        ComposerSettingPopover(
            accessibilityLabel: localized("設定"),
            accessibilityValue: "\(effortAccessibility.value)、\(permissionAccessibility.value)",
            accessibilityIdentifier: "newChat.settingsOverflow",
            showsFocusRing: true
        ) { _ in
            Image(systemName: "ellipsis")
                .font(DSFont.controlIcon)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        } content: { dismiss in
            ComposerPopupSurface(width: 340, padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    if !effortOptions.isEmpty {
                        Picker(localized("推論の深さ"), selection: $draft.settings.selectedEffort) {
                            if draft.settings.selectedEffort == nil {
                                Text(verbatim: localized("既定")).tag(nil as String?)
                            }
                            ForEach(effortOptions) { option in
                                Text(verbatim: option.title).tag(option.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("newChat.compactEffortPicker")
                        Divider()
                    }
                    permissionPanel(onClose: dismiss)
                }
            }
        }
    }

    private func permissionPanel(onClose: @escaping () -> Void) -> some View {
        ComposerPermissionPanel(
            agentRef: draft.agentRef, options: permissionOptions,
            currentValue: draft.settings.selectedPermissionProfile,
            isPlanOn: draft.settings.isPlanMode == true, isPlanAvailable: true,
            languageCode: languageCode,
            onSelect: { selectPermission($0.value) }, onPlanChange: setPlanMode, onClose: onClose
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newChat.permissionPanel")
    }

    private func projectPicker(isCompact: Bool) -> some View {
        SelectablePopoverButton(
            options: viewModel.projects.map { item in
                SelectablePopoverOption(
                    id: item.id.description,
                    value: item.id.description,
                    title: item.name,
                    isSelected: project?.id == item.id
                )
            } + [SelectablePopoverOption(
                id: Self.chooseFolderOptionID, value: nil, title: localized("フォルダを選ぶ…"),
                leadingSystemImage: "folder.badge.plus", isSelected: false
            )],
            selectedID: project?.id.description,
            accessibilityLabel: projectAccessibility.role,
            accessibilityValue: projectAccessibility.value,
            accessibilityIdentifier: "newChat.projectPicker",
            width: DSLayout.menuWidth,
            showsFocusRing: true,
            onSelect: { option in
                if option.id == Self.chooseFolderOptionID {
                    // ポップアップが閉じてからパネルを出す。
                    DispatchQueue.main.async { chooseFolder() }
                } else if let selectedProject = viewModel.projects.first(where: { $0.id.description == option.id }) {
                    selectProject(selectedProject.id)
                }
            }
        ) { _ in
            footerLabel(icon: "folder", title: destinationName ?? localized("プロジェクト"), compact: isCompact)
                .overlay {
                    if showsProjectError {
                        RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                            .strokeBorder(DSColor.attentionMark(.error), lineWidth: 1)
                    }
                }
        }
    }

    private func workspacePicker(isCompact: Bool) -> some View {
        let reason = localized("git リポジトリではないため worktree を作れません")
        return SelectablePopoverButton(
            options: [
                SelectablePopoverOption(
                    id: "directory", value: "false", title: localized("既存ディレクトリ"),
                    leadingSystemImage: "externaldrive", isSelected: !draft.usesWorktree
                ),
                SelectablePopoverOption(
                    id: "worktree", value: "true", title: localized("新しい worktree"),
                    detail: isGitRepository == false ? reason : nil,
                    leadingSystemImage: "arrow.triangle.branch", isSelected: draft.usesWorktree,
                    isEnabled: isGitRepository == true, accessibilityHint: isGitRepository == true ? nil : reason
                ),
            ],
            selectedID: draft.usesWorktree ? "worktree" : "directory",
            accessibilityLabel: workspaceAccessibility.role,
            accessibilityValue: workspaceAccessibility.value,
            accessibilityIdentifier: "newChat.workspacePicker",
            isEnabled: destinationDirectory != nil,
            showsFocusRing: true,
            onSelect: { selectWorkspace($0.value == "true") }
        ) { _ in
            footerLabel(
                icon: draft.usesWorktree ? "arrow.triangle.branch" : "externaldrive",
                title: draft.usesWorktree ? localized("新しい worktree") : localized("既存ディレクトリ"),
                compact: isCompact
            )
        }
    }

    private func footerLabel(icon: String, title: String, compact: Bool) -> some View {
        ComposerSettingChipLabel(title: title, systemImage: icon, compact: compact, usesMiddleTruncation: true)
    }

    private var sendButton: some View {
        Button {
            attemptSend()
        } label: {
            Image(systemName: "arrow.up")
                .font(DSFont.sendButtonIcon)
                .foregroundStyle(canSend ? DSColor.accentOnFill : DSColor.textTertiary)
                .frame(width: DSLayout.toolbarIconButtonSize, height: DSLayout.toolbarIconButtonSize)
                .contentShape(Circle())
                .overlay {
                    if newChatSendButtonInitiallyFocused || sendButtonFocused {
                        Circle()
                            .stroke(DSColor.focusRing, lineWidth: DSLayout.focusRingWidth)
                            .padding(-(DSLayout.focusRingGap + DSLayout.focusRingWidth / 2))
                    }
                }
        }
        .buttonStyle(NewChatSendButtonStyle(canSend: canSend))
        .focusable()
        .focused($sendButtonFocused)
        .focusEffectDisabled()
        .accessibilityLabel(Text("送信"))
        .accessibilityHint(Text(verbatim: sendUnavailableReason ?? ""))
        .accessibilityIdentifier("newChat.sendButton")
    }

    /// 提案チップの最後に「履歴から再開…」を並べ、1 行に収まらなければ 3 個ずつの 2 行に折り返す。
    private var suggestions: some View {
        let all = Array(NewChatSuggestions.all.enumerated())
        return ViewThatFits(in: .horizontal) {
            suggestionRow(all, includesHistory: true)
            VStack(spacing: DSSpacing.s) {
                suggestionRow(Array(all.prefix(3)), includesHistory: false)
                suggestionRow(Array(all.dropFirst(3)), includesHistory: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func suggestionRow(
        _ items: [(offset: Int, element: (title: String, text: String, symbol: String))],
        includesHistory: Bool
    ) -> some View {
        HStack(spacing: DSSpacing.s) {
            ForEach(items, id: \.offset) { index, suggestion in
                Button {
                    draft.appendSuggestion(suggestion.text)
                    focusToken &+= 1
                } label: {
                    suggestionChipLabel(title: localized(suggestion.title), symbol: suggestion.symbol)
                }
                .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: DSRadius.row))
                .accessibilityIdentifier("newChat.suggestion.\(index + 1)")
            }
            if includesHistory && showsHistoryResumeButton {
                historyResumeButton
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func suggestionChipLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(DSFont.meta)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(DSFont.auxiliary)
        }
        .foregroundStyle(DSColor.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: DSLayout.controlChipHeight)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                .strokeBorder(DSColor.controlBorder, lineWidth: DSLayout.suggestionChipBorderWidth)
        }
    }

    private var historyResumeButton: some View {
        Button {
            historyPopoverPresented = true
            Task { await loadHistoryEntries() }
        } label: {
            suggestionChipLabel(title: localized("履歴から再開…"), symbol: "clock.arrow.circlepath")
        }
        .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: DSRadius.row))
        .accessibilityIdentifier("newChat.historyResume")
        .popover(isPresented: $historyPopoverPresented, arrowEdge: .bottom) {
            if let project {
                NewChatHistoryPopover(
                    model: historyModel,
                    project: project,
                    usesWorktree: draft.usesWorktree,
                    locale: locale,
                    onRetry: { Task { await loadHistoryEntries() } },
                    onSelect: { resumeHistory($0.sessionID) },
                    entriesFilter: { viewModel.availableHistoryEntries($0, agentRef: draft.agentRef) }
                )
                .environment(\.locale, locale)
            }
        }
    }

    private func loadHistoryEntries() async {
        guard let project, historyKey != nil else { historyModel.reset(); return }
        await historyModel.load {
            try await viewModel.newChatHistoryEntries(projectID: project.id, agentRef: draft.agentRef)
        }
    }

    func selectModel(id: String) {
        for section in modelSections {
            if let model = section.models.first(where: { modelSelectionID($0, in: section) == id }) {
                selectModel(model, for: section)
                return
            }
        }
    }

    func selectModel(_ model: ControlModelOption, for section: NewChatModelMenuSection) {
        draft.selectHarness(.builtin(section.kind))
        draft.settings.selectedModel = model.id
        draft.settings.selectedEffort = newChatDefaultSettings(
            for: section.kind,
            modelID: model.id,
            fullAccess: BypassSettings.isEnabled(for: section.kind)
        ).selectedEffort
        modelSearch = ""
    }

    func selectEffort(_ value: String?) {
        draft.settings.selectedEffort = value
    }

    func selectPermission(_ value: String?) {
        draft.settings.isPlanMode = false
        draft.settings.selectedPermissionProfile = value
    }

    func setPlanMode(_ isOn: Bool) {
        draft.settings.isPlanMode = isOn
    }

    func selectProject(_ id: ProjectID) {
        draft.pendingFolderPath = nil
        router.newChatProjectID = id
    }

    static let chooseFolderOptionID = "chooseFolder"

    /// 選んだフォルダを送信先にする。プロジェクトは送信したときに作る（要件 FR-3）。
    private func chooseFolder() {
        guard let url = ProjectFolderPanel.choose(locale: locale) else { return }
        let path = url.standardizedFileURL.path
        if let existing = viewModel.projects.first(where: { $0.directoryURL.standardizedFileURL.path == path }) {
            selectProject(existing.id)
        } else {
            router.newChatProjectID = nil
            draft.pendingFolderPath = path
        }
    }



    func selectWorkspace(_ usesWorktree: Bool) {
        draft.usesWorktree = usesWorktree
    }

    private func cycleEffort() -> Bool {
        guard effortOptions.count > 1 else { return false }
        let currentIndex = effortOptions.firstIndex { $0.value == draft.settings.selectedEffort } ?? -1
        let next = effortOptions[(currentIndex + 1) % effortOptions.count]
        draft.settings.selectedEffort = next.value
        AccessibilityNotification.Announcement("\(localized("推論の深さ")) \(next.title)").post()
        return true
    }

    private func effortTitle(_ value: String) -> String {
        composerEffortTitle(value, languageCode: languageCode, bundle: localizationBundle)
    }

    /// ↩ と送信ボタン。送れないときは理由を検証メッセージとして出し、読み上げる（要件 E7）。
    private func attemptSend() {
        if canSend { send(); return }
        guard let reason = sendUnavailableReason else { return }
        showsSendValidation = true
        AccessibilityNotification.Announcement(reason).post()
    }

    private func send(workingDirectoryOverride: String? = nil) {
        guard canSend, !isLaunching else { return }
        isLaunching = true
        Task { @MainActor in
            do {
                guard let projectID = try await draft.projectIDForSendFromRuntime(selected: project?.id, in: viewModel) else {
                    isLaunching = false
                    return
                }
                router.newChatProjectID = projectID
                guard let request = draft.makeLaunchRequest(projectID: projectID, workingDirectoryOverride: workingDirectoryOverride) else {
                    isLaunching = false
                    return
                }
                isLaunching = false
                launch(request, isHistoryResume: false)
            } catch {
                isLaunching = false
                onLaunchFailure(draft.agentRef, error)
            }
        }
    }

    private func resumeHistory(_ historyID: String, workingDirectoryOverride: String? = nil) {
        guard !isLaunching, let project, selectedProjectExists(project.id) else { return }
        pendingResumeHistoryID = historyID
        historyPopoverPresented = false
        launch(NewChatLaunchRequest(
            projectID: project.id,
            agentRef: draft.agentRef,
            settings: draft.settings,
            usesWorktree: draft.usesWorktree,
            text: "",
            attachments: [],
            workingDirectoryOverride: workingDirectoryOverride,
            resumeHistoryID: historyID,
            worktreeStartPoint: draft.worktreeStartPoint(projectID: project.id, directory: destinationDirectory)
        ), isHistoryResume: true)
    }

    private func launch(_ request: NewChatLaunchRequest, isHistoryResume: Bool) {
        guard !isLaunching else { return }
        isLaunching = true
        AccessibilityNotification.Announcement(NewChatLaunchAnnouncement.text(
            phase: .starting, resumesHistory: isHistoryResume, locale: locale, bundle: localizationBundle
        )).post()
        Task {
            do {
                let id = try await DashboardViewModel.$reportsWorktreeCreation.withValue(true) {
                    try await viewModel.launchNewChat(request) { id in
                        router.completeNewChat(sessionID: id, projectID: request.projectID)
                    }
                }
                isLaunching = false
                pendingResumeHistoryID = nil
                let phase: NewChatLaunchAnnouncement.Phase
                if viewModel.sessionNode(id: id)?.appServer?.launchFailure != nil { phase = .failed }
                else if viewModel.isRuntimeProjection, !isHistoryResume { phase = .accepted }
                else { phase = .succeeded }
                AccessibilityNotification.Announcement(NewChatLaunchAnnouncement.text(
                    phase: phase, resumesHistory: isHistoryResume, locale: locale, bundle: localizationBundle
                )).post()
            } catch {
                if !isHistoryResume { draft.restoreLaunchDraft(from: request) }
                if let log = NewSessionCollisionGate.worktreeFailureLog(error) {
                    var existing: String?
                    if let repository = viewModel.projects.first(where: { $0.id == request.projectID })?.directoryURL {
                        existing = await NewSessionCollisionGate.existingWorktree(in: log, repository: repository)
                    }
                    spawnGuard = .worktreeFailed(
                        NewSessionRequest(ref: request.agentRef, projectID: request.projectID, backend: .appServer),
                        agentName: SpawnFailureDialogText.agentName(for: request.agentRef),
                        log: log,
                        existingWorktree: existing
                    )
                } else {
                    pendingResumeHistoryID = nil
                    onLaunchFailure(request.agentRef, error)
                }
                isLaunching = false
                AccessibilityNotification.Announcement(NewChatLaunchAnnouncement.text(
                    phase: .failed, resumesHistory: isHistoryResume, locale: locale, bundle: localizationBundle
                )).post()
            }
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalizedString.string(key, locale: locale, bundle: localizationBundle)
    }

    private func selectedProjectExists(_ id: ProjectID) -> Bool {
        viewModel.projects.contains { $0.id == id }
    }
}

struct NewChatAccessibilityCopy: Equatable {
    let role: String
    let value: String
}

enum NewChatLaunchAnnouncement {
    enum Phase { case starting, accepted, succeeded, failed }

    static func text(phase: Phase, resumesHistory: Bool, locale: Locale, bundle: Bundle = .main) -> String {
        let key: String
        switch (phase, resumesHistory) {
        case (.starting, true): key = "会話を再開しています"
        case (.starting, false): key = "起動しています。終わったら最初のメッセージを送ります"
        case (.succeeded, true): key = "会話を再開しました"
        case (.succeeded, false): key = "起動しました。最初のメッセージを送りました"
        case (.accepted, _): key = "メッセージを受け付けました。"
        case (.failed, true): key = "会話を再開できませんでした"
        case (.failed, false): key = "起動できませんでした。本文を入力欄に戻しました"
        }
        return AppLocalizedString.string(key, locale: locale, bundle: bundle)
    }
}

/// 見出しのドット書体（ADR 0191）。初回の参照で同梱の書体をプロセスに登録してから返す。
enum NewChatHeadingFont {
    static let postScriptName = "DotGothic16-Regular"
    static let font: Font = {
        if let url = Bundle.module.url(forResource: postScriptName, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return DSFont.newChatHeading
    }()
}

enum NewChatGreetings {
    static let all = [
        "何から始めますか？", "今日は何を進めますか？", "さあ、始めましょう", "次は何を作りますか？",
        "どこから手をつけますか？", "アイデアを形にしましょう", "今日の課題を教えてください",
        "どんな変更を加えますか？", "続きを進めましょう", "何をお手伝いしましょうか？",
    ]
    static func random() -> String { all.randomElement() ?? all[0] }
}

private enum NewChatSuggestions {
    static let all: [(title: String, text: String, symbol: String)] = [
        ("コードレビュー", "未コミットの変更をレビューして、問題点を重要度順に挙げてください。", "magnifyingglass"),
        ("バグ修正", "次の不具合を調べて、根本原因を直してください: ", "ladybug"),
        ("テスト追加", "次の機能にテストを追加してください: ", "checkmark.circle"),
        ("コードの説明", "このプロジェクトの構成と主な処理の流れを説明してください。", "book"),
        ("リファクタ", "次のコードを、振る舞いを変えずに読みやすく整理してください: ", "arrow.triangle.2.circlepath"),
    ]
}
