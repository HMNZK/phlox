import SwiftUI
import AppKit
import AgentDomain
import DesignSystem
import SessionFeature

struct NewChatView: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var draftStore: NewChatDraftStore
    @Bindable var draft: NewChatDraft
    let project: Project?
    let onLaunchFailure: (AgentRef, Error) -> Void

    @Environment(\.locale) private var locale
    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }
    @State private var greeting = NewChatGreetings.random()
    @State private var modelSearch = ""
    @State private var modelPickerPresented = false
    @FocusState private var modelSearchFocused: Bool
    @State private var inputFocused = false
    @State private var focusToken = 0
    @State private var isLaunching = false
    @State private var isGitRepository: Bool?
    @State private var spawnGuard: SpawnGuard?

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
        selectedModelOption?.displayName ?? draft.settings.selectedModel ?? AppLocalizedString.string("モデル", locale: locale)
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
            locale: locale
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
        let plan = AppLocalizedString.string("計画", locale: locale)
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
                ComposerSettingOption(value: nil, title: AppLocalizedString.string("既定", locale: locale)),
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
            ?? AppLocalizedString.string("既定", locale: locale)
    }
    private static let planSelection = "__plan"

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 620
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    AppIconBadge(showsCaution: false, size: 30)
                    Text(LocalizedStringKey(greeting))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                }
                .padding(.bottom, 20)
                composer(isCompact: compact)
                    .padding(.bottom, 16)
                suggestions
                Spacer(minLength: 12)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .onAppear {
                greeting = NewChatGreetings.random()
                focusToken &+= 1
            }
            .onChange(of: router.newChatFocusToken) { _, _ in
                focusToken &+= 1
            }
            .task(id: project?.directoryPath) {
                guard let project else { isGitRepository = nil; return }
                isGitRepository = await WorkingTreeService(repositoryRoot: project.directoryURL).isGitRepository()
            }
        }
    }

    private func composer(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerDraftInput(
                text: $draft.text,
                attachmentStore: draft.attachments,
                workingDirectory: suggestionDirectory ?? "",
                placeholder: AppLocalizedString.string("やりたいことを入力（/ でコマンド）", locale: locale),
                focusToken: focusToken,
                accessibilityPrefix: "newChat",
                inputAccessibilitySuffix: "messageInput",
                onSubmit: { send() },
                onCycleEffort: cycleEffort,
                onFocusChange: { inputFocused = $0 }
            )
            .id(suggestionControllerKey)
            .accessibilityIdentifier("newChat.composer")
            if let reason = sendUnavailableReason {
                Text(verbatim: reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .accessibilityIdentifier("newChat.sendUnavailableReason")
            }
            HStack(spacing: 5) {
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
            .padding(.bottom, 8)
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
                onCancel: { spawnGuard = nil; focusToken &+= 1 },
                onLaunch: { separates in
                    spawnGuard = nil
                    draft.usesWorktree = separates
                    send()
                },
                onUseWorktree: { path in
                    spawnGuard = nil
                    draft.usesWorktree = false
                    send(workingDirectoryOverride: path)
                }
            )
        }
    }

    private var harnessModelPicker: some View {
        Button { modelPickerPresented = true } label: {
            HStack(spacing: 6) {
                if let selectedKind { AgentBrandIcon(kind: selectedKind, size: 14, monochromeBuiltInMark: true) }
                Text(verbatim: selectedModelTitle)
                    .font(DSFont.auxiliary.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(DSColor.fillSubtle.opacity(modelPickerPresented ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(HoverableSoftButtonStyle())
        .popover(isPresented: $modelPickerPresented, arrowEdge: .top) { modelPickerMenu }
        .accessibilityLabel(Text(verbatim: "\(AppLocalizedString.string("ハーネスとモデル", locale: locale))、\(selectedSection?.name ?? "")：\(selectedModelTitle)"))
        .accessibilityValue(Text(verbatim: "\(selectedSection?.name ?? "") \(selectedModelTitle)"))
        .accessibilityIdentifier("newChat.harnessModelPicker")
        .help(Text(verbatim: "\(selectedSection?.name ?? "")：\(selectedModelTitle)"))
    }

    private var modelPickerMenu: some View {
        VStack(spacing: 6) {
            TextField(AppLocalizedString.string("モデルを絞り込む", locale: locale), text: $modelSearch)
                .textFieldStyle(.roundedBorder)
                .focused($modelSearchFocused)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .accessibilityIdentifier("newChat.modelSearch")
            List {
                ForEach(filteredModelSections) { section in
                    Section {
                        if section.isDetected {
                            ForEach(section.models, id: \.id) { model in
                                Button { selectModel(model, for: section) } label: {
                                    modelRow(model, section: section)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text(AppLocalizedString.string("未検出", locale: locale))
                                    .foregroundStyle(DSColor.textTertiary)
                                Text(String(format: AppLocalizedString.string("%@ が見つかりません。インストールすると選べます", locale: locale), section.name))
                                    .font(DSFont.meta)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            .disabled(true)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            AgentBrandIcon(kind: section.kind, size: 13, monochromeBuiltInMark: true)
                            Text(verbatim: section.name)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(width: 310, height: 340)
        }
        .frame(width: 310, height: 390)
        .onAppear { modelSearchFocused = true }
        .onDisappear { modelSearchFocused = false }
        .accessibilityIdentifier("newChat.modelMenu")
    }

    private var filteredModelSections: [NewChatModelMenuSection] {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return modelSections }
        return modelSections.compactMap { section in
            let models = section.models.filter { $0.id.lowercased().contains(query) || $0.displayName.lowercased().contains(query) }
            guard section.name.lowercased().contains(query) || !models.isEmpty else { return nil }
            return NewChatModelMenuSection(kind: section.kind, name: section.name, isDetected: section.isDetected,
                                           models: models, defaultModel: section.defaultModel)
        }
    }

    private func modelRow(_ model: ControlModelOption, section: NewChatModelMenuSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: draft.agentRef.builtinKind == section.kind && draft.settings.selectedModel == model.id ? "checkmark" : "")
                .font(DSFont.meta.weight(.semibold))
                .frame(width: 12)
            Text(verbatim: model.displayName)
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: 8)
            if model.id == section.defaultModel {
                Text(AppLocalizedString.string("既定", locale: locale))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .contentShape(Rectangle())
    }

    private var effortPicker: some View {
        ComposerSettingChip(
            title: effortTitle(draft.settings.selectedEffort ?? effortOptions.first?.value ?? ""),
            options: effortOptions,
            selection: draft.settings.selectedEffort,
            accessibilityIdentifier: "newChat.effortPicker",
            onSelect: { draft.settings.selectedEffort = $0 }
        )
        .accessibilityLabel(Text(verbatim: "\(AppLocalizedString.string("推論の深さ", locale: locale)): \(effortTitle(draft.settings.selectedEffort ?? ""))"))
    }

    private var permissionPicker: some View {
        ComposerSettingChip(
            title: selectedPermissionTitle,
            options: permissionOptions,
            selection: selectedPermissionSelection,
            accessibilityIdentifier: "newChat.permissionPicker",
            onSelect: selectPermission
        )
        .accessibilityLabel(Text(verbatim: "\(AppLocalizedString.string(selectedKind == .cursor ? "mode" : "権限", locale: locale)): \(selectedPermissionTitle)"))
    }

    private var compactSettingsMenu: some View {
        Menu {
            if !effortOptions.isEmpty {
                Menu(AppLocalizedString.string("推論の深さ", locale: locale)) {
                    ForEach(effortOptions) { option in
                        settingMenuButton(option, selected: draft.settings.selectedEffort == option.value) {
                            draft.settings.selectedEffort = option.value
                        }
                    }
                }
            }
            Menu(AppLocalizedString.string(selectedKind == .cursor ? "mode" : "権限", locale: locale)) {
                ForEach(permissionOptions) { option in
                    settingMenuButton(option, selected: selectedPermissionSelection == option.value) {
                        selectPermission(option.value)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("設定"))
        .accessibilityIdentifier("newChat.settingsOverflow")
    }

    private func settingMenuButton(_ option: ComposerSettingOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "").frame(width: 12)
                Text(verbatim: option.title)
            }
        }
        .disabled(!option.isEnabled)
    }

    private func projectPicker(isCompact: Bool) -> some View {
        Menu {
            ForEach(viewModel.projects) { item in
                Button {
                    router.showNewChat(projectID: item.id)
                } label: {
                    HStack {
                        if project?.id == item.id { Image(systemName: "checkmark") }
                        Text(verbatim: item.name)
                        if draftStore.hasDraft(for: item.id) {
                            Text(AppLocalizedString.string("下書きあり", locale: locale))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            }
            Text(AppLocalizedString.string("本文と添付はプロジェクトごとに保たれます", locale: locale))
                .font(.system(size: 10.5))
                .foregroundStyle(DSColor.textSecondary)
        } label: {
            footerLabel(icon: "folder", title: project?.name ?? AppLocalizedString.string("プロジェクト", locale: locale), compact: isCompact)
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.projects.isEmpty)
        .accessibilityLabel(Text(verbatim: "\(AppLocalizedString.string("プロジェクト", locale: locale)): \(project?.name ?? AppLocalizedString.string("未選択", locale: locale))"))
        .accessibilityIdentifier("newChat.projectPicker")
    }

    private func workspacePicker(isCompact: Bool) -> some View {
        Menu {
            Button {
                draft.usesWorktree = false
            } label: {
                if !draft.usesWorktree { Label(AppLocalizedString.string("既存ディレクトリ", locale: locale), systemImage: "checkmark") }
                else { Text(AppLocalizedString.string("既存ディレクトリ", locale: locale)) }
            }
            Button {
                draft.usesWorktree = true
            } label: {
                if draft.usesWorktree { Label(AppLocalizedString.string("新しい worktree", locale: locale), systemImage: "checkmark") }
                else { Text(AppLocalizedString.string("新しい worktree", locale: locale)) }
            }
            .disabled(isGitRepository != true)
            .accessibilityHint(Text(isGitRepository == true ? "" : AppLocalizedString.string("git リポジトリではないため worktree を作れません", locale: locale)))
            if isGitRepository == false {
                Text(AppLocalizedString.string("git リポジトリではないため worktree を作れません", locale: locale))
                    .font(DSFont.meta)
            }
        } label: {
            footerLabel(icon: draft.usesWorktree ? "arrow.triangle.branch" : "folder", title: draft.usesWorktree
                ? AppLocalizedString.string("新しい worktree", locale: locale)
                : AppLocalizedString.string("既存ディレクトリ", locale: locale), compact: isCompact)
        }
        .menuStyle(.borderlessButton)
        .disabled(project == nil)
        .accessibilityLabel(Text(verbatim: "\(AppLocalizedString.string("作業場所", locale: locale)): \(draft.usesWorktree ? AppLocalizedString.string("新しい worktree", locale: locale) : AppLocalizedString.string("既存ディレクトリ", locale: locale))"))
        .accessibilityIdentifier("newChat.workspacePicker")
    }

    private func footerLabel(icon: String, title: String, compact: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(DSFont.auxiliary)
            if !compact {
                Text(verbatim: title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(DSColor.textSecondary)
        .padding(.horizontal, compact ? 5 : 7)
        .frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private var sendButton: some View {
        Button(action: { send() }) {
            Image(systemName: "arrow.up")
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(canSend ? Color.white : DSColor.textTertiary)
                .frame(width: 28, height: 28)
                .background(canSend ? DSColor.accentFill : DSColor.fillSubtle, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(HoverableSurfaceButtonStyle())
        .disabled(!canSend)
        .accessibilityLabel(Text("送信"))
        .accessibilityIdentifier("newChat.sendButton")
    }

    private var suggestions: some View {
        HStack(spacing: 7) {
            ForEach(Array(NewChatSuggestions.all.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    draft.appendSuggestion(suggestion.text)
                    focusToken &+= 1
                } label: {
                    Text(LocalizedStringKey(suggestion.title))
                        .font(DSFont.auxiliary.weight(.medium))
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(DSColor.fillSubtle.opacity(0.65), in: Capsule())
                }
                .buttonStyle(HoverableSoftButtonStyle())
                .accessibilityIdentifier("newChat.suggestion.\(index + 1)")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func selectModel(_ model: ControlModelOption, for section: NewChatModelMenuSection) {
        draft.selectHarness(.builtin(section.kind))
        draft.settings.selectedModel = model.id
        draft.settings.selectedEffort = model.defaultReasoningEffort ?? (section.kind == .claudeCode && model.id != "haiku" ? "high" : nil)
        modelSearch = ""
        modelPickerPresented = false
    }

    private func selectPermission(_ value: String?) {
        if value == Self.planSelection {
            draft.settings.isPlanMode = true
        } else {
            draft.settings.isPlanMode = false
            draft.settings.selectedPermissionProfile = value
        }
    }

    private func cycleEffort() -> Bool {
        guard effortOptions.count > 1 else { return false }
        let currentIndex = effortOptions.firstIndex { $0.value == draft.settings.selectedEffort } ?? -1
        let next = effortOptions[(currentIndex + 1) % effortOptions.count]
        draft.settings.selectedEffort = next.value
        AccessibilityNotification.Announcement("\(AppLocalizedString.string("推論の深さ", locale: locale)) \(next.title)").post()
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
        return AppLocalizedString.string(key, locale: locale)
    }

    private func send(workingDirectoryOverride: String? = nil) {
        guard canSend, let project, selectedProjectExists(project.id),
              let request = draft.makeLaunchRequest(projectID: project.id, workingDirectoryOverride: workingDirectoryOverride) else { return }
        isLaunching = true
        AccessibilityNotification.Announcement(AppLocalizedString.string("起動しています。終わったら最初のメッセージを送ります", locale: locale)).post()
        Task {
            do {
                let id = try await DashboardViewModel.$reportsWorktreeCreation.withValue(true) {
                    try await viewModel.launchNewChat(request) { id in
                        router.completeNewChat(sessionID: id, projectID: request.projectID)
                    }
                }
                isLaunching = false
                if viewModel.sessionNode(id: id)?.appServer?.launchFailure != nil {
                    AccessibilityNotification.Announcement(AppLocalizedString.string("起動できませんでした。本文を入力欄に戻しました", locale: locale)).post()
                } else {
                    AccessibilityNotification.Announcement(AppLocalizedString.string("起動しました。最初のメッセージを送りました", locale: locale)).post()
                }
            } catch {
                draft.restoreLaunchDraft(from: request)
                if let log = NewSessionCollisionGate.worktreeFailureLog(error) {
                    let existing = await NewSessionCollisionGate.existingWorktree(in: log, repository: project.directoryURL)
                    spawnGuard = .worktreeFailed(
                        NewSessionRequest(ref: request.agentRef, projectID: request.projectID, backend: .appServer),
                        agentName: SpawnFailureDialogText.agentName(for: request.agentRef),
                        log: log,
                        existingWorktree: existing
                    )
                } else {
                    onLaunchFailure(request.agentRef, error)
                }
                isLaunching = false
                AccessibilityNotification.Announcement(AppLocalizedString.string("起動できませんでした。本文を入力欄に戻しました", locale: locale)).post()
            }
        }
    }

    private func selectedProjectExists(_ id: ProjectID) -> Bool {
        viewModel.projects.contains { $0.id == id }
    }
}

private enum NewChatGreetings {
    static let all = [
        "何から始めますか？", "今日は何を進めますか？", "さあ、始めましょう", "次は何を作りますか？",
        "どこから手をつけますか？", "アイデアを形にしましょう", "今日の課題を教えてください",
        "どんな変更を加えますか？", "続きを進めましょう", "何をお手伝いしましょうか？",
    ]
    static func random() -> String { all.randomElement() ?? all[0] }
}

private enum NewChatSuggestions {
    static let all: [(title: String, text: String)] = [
        ("コードレビュー", "未コミットの変更をレビューして、問題点を重要度順に挙げてください。"),
        ("バグ修正", "次の不具合を調べて、根本原因を直してください: "),
        ("テスト追加", "次の機能にテストを追加してください: "),
        ("コードの説明", "このプロジェクトの構成と主な処理の流れを説明してください。"),
        ("リファクタ", "次のコードを、振る舞いを変えずに読みやすく整理してください: "),
    ]
}
