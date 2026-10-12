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

extension EnvironmentValues {
    var newChatSendButtonInitiallyFocused: Bool {
        get { self[NewChatSendButtonInitiallyFocusedKey.self] }
        set { self[NewChatSendButtonInitiallyFocusedKey.self] = newValue }
    }
    var newChatModelMenuInitiallyOpen: Bool {
        get { self[NewChatModelMenuInitiallyOpenKey.self] }
        set { self[NewChatModelMenuInitiallyOpenKey.self] = newValue }
    }
}

private struct NewChatChipLabel: View {
    let title: String?
    let systemImage: String?
    let harnessKind: AgentKind?
    let compact: Bool
    let usesMiddleTruncation: Bool

    init(
        title: String?,
        systemImage: String? = nil,
        harnessKind: AgentKind? = nil,
        compact: Bool = false,
        usesMiddleTruncation: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.harnessKind = harnessKind
        self.compact = compact
        self.usesMiddleTruncation = usesMiddleTruncation
    }

    var body: some View {
        HStack(spacing: DSLayout.controlChipContentGap) {
            if let harnessKind {
                AgentBrandIcon(kind: harnessKind, size: DSLayout.controlChipIconSize)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(DSFont.controlIcon)
                    .frame(width: DSLayout.controlChipIconSize, height: DSLayout.controlChipIconSize)
                    .accessibilityHidden(true)
            }
            if let title, !compact {
                Text(verbatim: title)
                    .font(DSFont.auxiliary)
                    .lineLimit(1)
                    .truncationMode(usesMiddleTruncation ? .middle : .tail)
            }
            Image(systemName: "chevron.down")
                .font(DSFont.controlChevron)
                .frame(width: DSLayout.controlChipChevronSize, height: DSLayout.controlChipChevronSize)
                .accessibilityHidden(true)
        }
        .foregroundStyle(DSColor.textSecondary)
        .padding(.horizontal, DSLayout.controlChipHorizontalPadding)
        .frame(height: DSLayout.controlChipHeight)
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
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
            guard canSend else { return DSColor.fillSubtle }
            if configuration.isPressed { return DSColor.sendPressedFill }
            if isHovering { return DSColor.sendHoverFill }
            return DSColor.accentFill
        }
    }
}

struct NewChatView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var draftStore: NewChatDraftStore
    @Bindable var draft: NewChatDraft
    let project: Project?
    let onLaunchFailure: (AgentRef, Error) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.newChatSendButtonInitiallyFocused) private var newChatSendButtonInitiallyFocused
    @Environment(\.newChatModelMenuInitiallyOpen) private var newChatModelMenuInitiallyOpen
    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }
    @State private var greeting = NewChatGreetings.random()
    @State private var modelSearch = ""
    @FocusState private var sendButtonFocused: Bool
    @FocusState private var harnessPickerFocused: Bool
    @State private var inputFocused = false
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
        .init(role: localized("プロジェクト"), value: project?.name ?? localized("未選択"))
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
            projectExists: project.map { selectedProjectExists($0.id) } ?? false,
            harnessDetected: detectedHarnessIDs.contains(draft.agentRef.id),
            modelAcceptsImages: modelAcceptsImages
        ) && !isLaunching
    }
    private var sendUnavailableReason: String? {
        draft.sendUnavailableReason(
            projectExists: project.map { selectedProjectExists($0.id) } ?? false,
            harnessDetected: detectedHarnessIDs.contains(draft.agentRef.id),
            modelAcceptsImages: modelAcceptsImages,
            locale: locale,
            bundle: localizationBundle
        )
    }
    private var suggestionDirectory: String? {
        project.map { NewChatSuggestionDirectory.path(projectDirectory: $0.directoryPath, usesWorktree: draft.usesWorktree) }
    }
    private var suggestionControllerKey: String? {
        suggestionDirectory.map { "\($0):\(draft.usesWorktree)" }
    }
    private var effortOptions: [ComposerSettingOption] {
        guard let kind = selectedKind else { return [] }
        let values: [String]
        switch kind {
        case .claudeCode:
            let model = (draft.settings.selectedModel ?? "").split(separator: "[", maxSplits: 1).first.map(String.init) ?? draft.settings.selectedModel
            values = model == "haiku" ? [] : ["low", "medium", "high", "xhigh", "max"]
        case .codex, .cursor:
            values = selectedModelOption?.reasoningEfforts ?? []
        }
        let available = values.map { ComposerSettingOption(value: $0, title: effortTitle($0)) }
        guard let selected = draft.settings.selectedEffort, !available.contains(where: { $0.value == selected }) else { return available }
        return available + [ComposerSettingOption(value: selected, title: effortTitle(selected))]
    }
    private var permissionOptions: [ComposerSettingOption] {
        guard let kind = selectedKind else { return [] }
        let plan = "Plan"
        func permission(_ value: String, agent: UIWording.PermissionAgent, kind: UIWording.PermissionKind) -> ComposerSettingOption {
            ComposerSettingOption(
                value: value,
                title: UIWording.permission(agent: agent, kind: kind, value: value, languageCode: languageCode).title
            )
        }
        switch kind {
        case .claudeCode:
            let values = ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk"]
            return values.map { permission($0, agent: .claude, kind: .claudePermissionMode) }
                + [ComposerSettingOption(value: Self.planSelection, title: plan)]
        case .codex:
            return [":danger-full-access", ":workspace", ":read-only"].map {
                permission($0, agent: .codex, kind: .codexProfile)
            } + [ComposerSettingOption(value: Self.planSelection, title: plan)]
        case .cursor:
            return [
                ComposerSettingOption(value: nil, title: localized("既定")),
                permission("ask", agent: .cursor, kind: .cursorOperationMode),
                ComposerSettingOption(value: Self.planSelection, title: plan),
            ]
        }
    }
    private var selectedPermissionSelection: String? {
        draft.settings.isPlanMode == true ? Self.planSelection : draft.settings.selectedPermissionProfile
    }
    private var selectedPermissionTitle: String {
        permissionOptions.first(where: { $0.value == selectedPermissionSelection })?.title
            ?? localized("既定")
    }
    private var historyKey: String? {
        guard let project, draft.agentRef == .builtin(.claudeCode) || draft.agentRef == .builtin(.codex) else { return nil }
        return ([project.id.description, draft.agentRef.id, project.directoryPath] + (project.worktreePaths ?? [])).joined(separator: "\u{1f}")
    }
    private var showsHistoryResumeButton: Bool {
        historyKey != nil && (historyModel.state != .empty || historyPopoverPresented)
    }
    private static let planSelection = "__plan"

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 620
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Text(verbatim: localized(greeting))
                        .font(DSFont.heroTitle)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                }
                .padding(.bottom, 20)
                composer(isCompact: compact)
                    .padding(.bottom, 16)
                suggestions
                historyResumeButton
                Spacer(minLength: 12)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .onAppear {
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
            .task(id: project?.directoryPath) {
                guard let project else { isGitRepository = nil; return }
                isGitRepository = await WorkingTreeService(repositoryRoot: project.directoryURL).isGitRepository()
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

    private func composer(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerDraftInput(
                text: $draft.text,
                attachmentStore: draft.attachments,
                workingDirectory: suggestionDirectory ?? "",
                placeholder: localized("やりたいことを入力（/ でコマンド）"),
                focusToken: focusToken,
                accessibilityPrefix: "newChat",
                inputAccessibilitySuffix: "messageInput",
                onSubmit: { send() },
                onCycleEffort: cycleEffort,
                onFocusChange: { inputFocused = $0 },
                onTab: { harnessPickerFocused = true; return true }
            )
            .id(suggestionControllerKey)
            .accessibilityIdentifier("newChat.composer")
            if let reason = sendUnavailableReason {
                Text(verbatim: reason)
                    .font(DSFont.row)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .accessibilityIdentifier("newChat.sendUnavailableReason")
            }
            HStack(spacing: DSSpacing.chip) {
                ComposerAttachPlaceholder(
                    text: $draft.text,
                    attachmentStore: draft.attachments,
                    agentRef: draft.agentRef,
                    imageAttachmentsSupported: selectedKind != .cursor,
                    accessibilityIdentifier: "newChat.attachments"
                )
                harnessModelPicker
                if isCompact {
                    compactSettingsMenu
                } else {
                    if !effortOptions.isEmpty { effortPicker }
                    permissionPicker
                }
                Spacer(minLength: 6)
                projectPicker(isCompact: isCompact)
                workspacePicker(isCompact: isCompact)
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 3)
            .padding(.bottom, 14)
            .focusSection()
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(DSColor.fieldBackground)
                .overlay(shape.strokeBorder(DSColor.fieldBorder, lineWidth: 1))
        }
        .background {
            if inputFocused {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(DSColor.focusRing)
                    .padding(-3)
            }
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

    private var harnessModelPicker: some View {
        SelectablePopoverButton(
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
            showsFocusRing: true,
            onSelect: { selectModel(id: $0.id) }
        ) { _ in
            NewChatChipLabel(title: selectedModelTitle, harnessKind: selectedKind)
        }
        .focused($harnessPickerFocused)
    }

    private var modelPickerFooter: String {
        locale.language.languageCode?.identifier == "en"
            ? "↑↓ Move · ↩ Select · Type to filter · Esc Close"
            : "↑↓ 移動 · ↩ 決定 · 文字入力で絞り込み · Esc 閉じる"
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
        ComposerSettingChip(
            title: selectedPermissionTitle,
            options: permissionOptions,
            selection: selectedPermissionSelection,
            accessibilityIdentifier: "newChat.permissionPicker",
            leadingSystemImage: "shield",
            showsFocusRing: true,
            onSelect: selectPermission
        )
        .accessibilityLabel(Text(verbatim: permissionAccessibility.role))
        .accessibilityValue(Text(verbatim: permissionAccessibility.value))
    }

    private var compactSettingsMenu: some View {
        SelectablePopoverButton(
            options: compactSettingsOptions,
            selectedID: compactSettingsSelectedID,
            accessibilityLabel: localized("設定"),
            accessibilityValue: "\(effortAccessibility.value)、\(permissionAccessibility.value)",
            accessibilityIdentifier: "newChat.settingsOverflow",
            width: DSLayout.menuWidth,
            showsFocusRing: true,
            onSelect: selectCompactSetting
        ) { _ in
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
    }

    private var compactSettingsOptions: [SelectablePopoverOption] {
        let efforts = effortOptions.map { option in
            SelectablePopoverOption(
                id: "effort:\(option.id)", value: option.value, title: option.title,
                sectionTitle: localized("推論の深さ"), isSelected: draft.settings.selectedEffort == option.value,
                isEnabled: option.isEnabled
            )
        }
        let permissions = permissionOptions.map { option in
            SelectablePopoverOption(
                id: "permission:\(option.id)", value: option.value, title: option.title,
                sectionTitle: localized(selectedKind == .cursor ? "mode" : "権限"),
                isSelected: selectedPermissionSelection == option.value, isEnabled: option.isEnabled
            )
        }
        return efforts + permissions
    }

    private var compactSettingsSelectedID: String? {
        if let option = effortOptions.first(where: { $0.value == draft.settings.selectedEffort }) { return "effort:\(option.id)" }
        if let option = permissionOptions.first(where: { $0.value == selectedPermissionSelection }) { return "permission:\(option.id)" }
        return nil
    }

    private func selectCompactSetting(_ option: SelectablePopoverOption) {
        if option.id.hasPrefix("effort:") { selectEffort(option.value) }
        else { selectPermission(option.value) }
    }

    private func projectPicker(isCompact: Bool) -> some View {
        SelectablePopoverButton(
            options: viewModel.projects.map { item in
                SelectablePopoverOption(
                    id: item.id.description,
                    value: item.id.description,
                    title: item.name,
                    badge: draftStore.hasDraft(for: item.id) ? localized("下書きあり") : nil,
                    isSelected: project?.id == item.id
                )
            },
            selectedID: project?.id.description,
            accessibilityLabel: projectAccessibility.role,
            accessibilityValue: projectAccessibility.value,
            accessibilityIdentifier: "newChat.projectPicker",
            width: DSLayout.menuWidth,
            footer: localized("本文と添付はプロジェクトごとに保たれます"),
            isEnabled: !viewModel.projects.isEmpty,
            showsFocusRing: true,
            onSelect: { option in
                if let selectedProject = viewModel.projects.first(where: { $0.id.description == option.id }) {
                    selectProject(selectedProject.id)
                }
            }
        ) { _ in
            footerLabel(icon: "folder", title: project?.name ?? localized("プロジェクト"), compact: isCompact)
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
            isEnabled: project != nil,
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
        NewChatChipLabel(title: title, systemImage: icon, compact: compact, usesMiddleTruncation: true)
    }

    private var sendButton: some View {
        Button {
            guard canSend else { return }
            send()
        } label: {
            Image(systemName: "arrow.up")
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(canSend ? Color.white : DSColor.textTertiary)
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

    private var suggestions: some View {
        HStack(spacing: DSSpacing.s) {
            ForEach(Array(NewChatSuggestions.all.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    draft.appendSuggestion(suggestion.text)
                    focusToken &+= 1
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: suggestion.symbol)
                            .font(DSFont.meta)
                            .accessibilityHidden(true)
                        Text(verbatim: localized(suggestion.title))
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
                .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: DSRadius.row))
                .accessibilityIdentifier("newChat.suggestion.\(index + 1)")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var historyResumeButton: some View {
        Group {
            if showsHistoryResumeButton {
                Button {
                    historyPopoverPresented = true
                    Task { await loadHistoryEntries() }
                } label: {
                    Text("履歴から再開…")
                        .font(DSFont.auxiliary.weight(.medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newChat.historyResume")
                .popover(isPresented: $historyPopoverPresented, arrowEdge: .bottom) {
                    if let project {
                        NewChatHistoryPopover(
                            model: historyModel,
                            project: project,
                            usesWorktree: draft.usesWorktree,
                            locale: locale,
                            onRetry: { Task { await loadHistoryEntries() } },
                            onSelect: { resumeHistory($0.sessionID) }
                        )
                        .environment(\.locale, locale)
                    }
                }
            } else {
                Color.clear
                    .frame(height: 24)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
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
        draft.settings.selectedEffort = model.defaultReasoningEffort ?? (section.kind == .claudeCode && model.id != "haiku" ? "high" : nil)
        modelSearch = ""
    }

    func selectEffort(_ value: String?) {
        draft.settings.selectedEffort = value
    }

    func selectPermission(_ value: String?) {
        if value == Self.planSelection {
            draft.settings.isPlanMode = true
        } else {
            draft.settings.isPlanMode = false
            draft.settings.selectedPermissionProfile = value
        }
    }

    func selectProject(_ id: ProjectID) {
        router.showNewChat(projectID: id)
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
        let key: String
        switch value {
        case "low": key = "低"
        case "medium": key = "中"
        case "high": key = "高"
        case "xhigh": key = "非常に高"
        case "max": key = "最大"
        case "ultra": key = "ultra"
        default: return value
        }
        return localized(key)
    }

    private func send(workingDirectoryOverride: String? = nil) {
        guard canSend, let project, selectedProjectExists(project.id),
              let request = draft.makeLaunchRequest(projectID: project.id, workingDirectoryOverride: workingDirectoryOverride) else { return }
        launch(request, isHistoryResume: false)
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
            resumeHistoryID: historyID
        ), isHistoryResume: true)
    }

    private func launch(_ request: NewChatLaunchRequest, isHistoryResume: Bool) {
        guard !isLaunching, let project else { return }
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
                let phase: NewChatLaunchAnnouncement.Phase = viewModel.sessionNode(id: id)?.appServer?.launchFailure == nil ? .succeeded : .failed
                AccessibilityNotification.Announcement(NewChatLaunchAnnouncement.text(
                    phase: phase, resumesHistory: isHistoryResume, locale: locale, bundle: localizationBundle
                )).post()
            } catch {
                if !isHistoryResume { draft.restoreLaunchDraft(from: request) }
                if let log = NewSessionCollisionGate.worktreeFailureLog(error) {
                    let existing = await NewSessionCollisionGate.existingWorktree(in: log, repository: project.directoryURL)
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
    enum Phase { case starting, succeeded, failed }

    static func text(phase: Phase, resumesHistory: Bool, locale: Locale, bundle: Bundle = .main) -> String {
        let key: String
        switch (phase, resumesHistory) {
        case (.starting, true): key = "会話を再開しています"
        case (.starting, false): key = "起動しています。終わったら最初のメッセージを送ります"
        case (.succeeded, true): key = "会話を再開しました"
        case (.succeeded, false): key = "起動しました。最初のメッセージを送りました"
        case (.failed, true): key = "会話を再開できませんでした"
        case (.failed, false): key = "起動できませんでした。本文を入力欄に戻しました"
        }
        return AppLocalizedString.string(key, locale: locale, bundle: bundle)
    }
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
