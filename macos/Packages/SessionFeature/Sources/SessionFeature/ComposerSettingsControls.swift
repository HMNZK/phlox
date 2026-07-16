import SwiftUI
import AppKit
import AgentDomain
import CodexAppServerKit
import DesignSystem
import UniformTypeIdentifiers

/// コンポーザー設定コントロールの種別。agentRef ごとに出す集合は `composerControls(for:)` が単一の真実源。
enum ComposerControlKind: Equatable, CaseIterable {
    case model
    case effort
    case permission
    case plan
    case mode
}

struct ComposerModeOption: Hashable {
    let value: String?
    let title: String
    let isPlan: Bool
}

/// agentRef ごとに表示する設定コントロール集合（単一表示・グリッド表示の共通真実源）。
func composerControls(for agentRef: AgentRef) -> [ComposerControlKind] {
    switch agentRef {
    case .builtin(.codex):
        [.model, .permission]
    case .builtin(.claudeCode):
        [.model, .effort, .permission]
    case .builtin(.cursor):
        [.model, .mode]
    default:
        []
    }
}

func composerModeOptions(for agentRef: AgentRef, codexProfileIDs: [String]) -> [ComposerModeOption] {
    switch agentRef {
    case .builtin(.codex):
        codexProfileIDs.map {
            ComposerModeOption(value: $0, title: composerPermissionTitle(for: $0), isPlan: false)
        } + [
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ]
    case .builtin(.claudeCode):
        [
            ComposerModeOption(value: "acceptEdits", title: "Accept Edits", isPlan: false),
            ComposerModeOption(value: "bypassPermissions", title: "Bypass", isPlan: false),
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ]
    case .builtin(.cursor):
        [
            ComposerModeOption(value: nil, title: "Run Everything", isPlan: false),
            ComposerModeOption(value: "ask", title: "Ask", isPlan: false),
            ComposerModeOption(value: "plan", title: "Plan", isPlan: true),
        ]
    default:
        []
    }
}

func composerPermissionTitle(for id: String?) -> String {
    switch id {
    case ":read-only": "Read Only"
    case ":workspace": "Auto"
    case ":danger-full-access": "Full Access"
    case .some(let value): value
    case nil: "Approval"
    }
}

enum ComposerControlSide {
    case leading
    case trailing
}

/// フッター左右分割の単一真実源。trailing = {.model, .effort}、leading = 残り（いずれも元の順序を保持）。
func composerControls(for agentRef: AgentRef, side: ComposerControlSide) -> [ComposerControlKind] {
    let all = composerControls(for: agentRef)
    switch side {
    case .trailing:
        return all.filter { $0 == .model || $0 == .effort }
    case .leading:
        return all.filter { $0 != .model && $0 != .effort }
    }
}

enum ComposerSettingsLayout {
    case standard
    case compact
}

/// 単一表示・グリッド表示で共有するコンポーザー設定コントロール群。
struct ComposerSettingsControlsView: View {
    @Bindable var viewModel: ChatSessionViewModel
    var layout: ComposerSettingsLayout = .standard
    var side: ComposerControlSide
    var accessibilityPrefix: String = "ChatComposer"

    private var controls: [ComposerControlKind] {
        composerControls(for: viewModel.agentRef, side: side)
    }

    private var showsAttachPlaceholder: Bool {
        side == .leading
    }

    var body: some View {
        if controls.isEmpty && !showsAttachPlaceholder {
            EmptyView()
        } else {
            HStack(spacing: layout == .compact ? DSSpacing.xs : DSSpacing.s) {
                if showsAttachPlaceholder {
                    ComposerAttachPlaceholder(
                        viewModel: viewModel,
                        layout: layout,
                        accessibilityIdentifier: "\(accessibilityPrefix).attachPlaceholder"
                    )
                }
                ForEach(controls, id: \.self) { kind in
                    controlView(for: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func controlView(for kind: ComposerControlKind) -> some View {
        switch kind {
        case .model:
            switch viewModel.agentRef {
            case .builtin(.codex):
                modelMenu
            default:
                spawnModelMenu
            }
        case .effort:
            if !viewModel.claudeEffortLevels.isEmpty {
                claudeEffortMenu
            }
        case .permission:
            switch viewModel.agentRef {
            case .builtin(.codex):
                permissionMenu
            default:
                claudePermissionMenu
            }
        case .mode:
            cursorModeMenu
        case .plan:
            EmptyView()
        }
    }

    // MARK: - Spawn agent (Claude/Cursor) menus

    private var spawnModelMenu: some View {
        HoverableComposerControl(isEnabled: !viewModel.availableSpawnAgentModels.isEmpty) { isHovering in
            Menu {
                ForEach(viewModel.availableSpawnAgentModels, id: \.self) { model in
                    Button {
                        setSpawnModel(model)
                    } label: {
                        SettingsMenuRow(
                            title: viewModel.spawnAgentModelDisplayName(model),
                            isSelected: model == viewModel.selectedModel
                        )
                    }
                }
            } label: {
                ComposerControlChip(
                    title: viewModel.selectedModel.map(viewModel.spawnAgentModelDisplayName) ?? "Model",
                    detail: nil,
                    emphasis: .plain,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.availableSpawnAgentModels.isEmpty)
            .accessibilityIdentifier("\(accessibilityPrefix).spawnModelMenu")
        }
    }

    private var claudeEffortMenu: some View {
        HoverableComposerControl { isHovering in
            Menu {
                ForEach(viewModel.claudeEffortLevels, id: \.self) { effort in
                    Button {
                        setSpawnEffort(effort)
                    } label: {
                        SettingsMenuRow(
                            title: Self.spawnEffortTitle(for: effort),
                            isSelected: effort == viewModel.selectedEffort
                        )
                    }
                }
            } label: {
                ComposerControlChip(
                    title: viewModel.selectedEffort.map(Self.spawnEffortTitle) ?? "Effort",
                    detail: nil,
                    emphasis: .plain,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("\(accessibilityPrefix).claudeEffortMenu")
        }
    }

    private var claudePermissionMenu: some View {
        HoverableComposerControl { isHovering in
            Menu {
                ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: []), id: \.self) { option in
                    Button {
                        setSpawnPermission(option.value)
                    } label: {
                        SettingsMenuRow(
                            title: option.title,
                            isSelected: modeOptionIsSelected(option, currentValue: selectedClaudePermission)
                        )
                    }
                    .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
                }
            } label: {
                ComposerControlChip(
                    title: viewModel.isPlanMode ? "Plan" : Self.claudePermissionTitle(for: selectedClaudePermission),
                    detail: nil,
                    emphasis: .pill,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("\(accessibilityPrefix).claudePermissionMenu")
        }
    }

    private var cursorModeMenu: some View {
        HoverableComposerControl { isHovering in
            Menu {
                ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: []), id: \.self) { option in
                    Button {
                        setSpawnPermission(option.value)
                    } label: {
                        SettingsMenuRow(
                            title: option.title,
                            isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile)
                        )
                    }
                    .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
                }
            } label: {
                ComposerControlChip(
                    title: viewModel.isPlanMode ? "Plan" : Self.cursorModeTitle(for: viewModel.selectedPermissionProfile),
                    detail: nil,
                    emphasis: .pill,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("\(accessibilityPrefix).cursorModeMenu")
        }
    }

    private var selectedClaudePermission: String {
        viewModel.selectedPermissionProfile ?? Self.claudeDefaultPermission
    }

    // MARK: - Codex app-server menus

    private var selectedModel: AppServerModel? {
        guard let selected = viewModel.selectedModel else { return nil }
        return viewModel.availableModels.first { $0.id == selected || $0.model == selected }
    }

    private var modelTitle: String {
        selectedModel?.displayName ?? viewModel.selectedModel ?? "Model"
    }

    private var selectedEffortTitle: String? {
        viewModel.selectedEffort.map(Self.reasoningEffortTitle)
    }

    private var selectedPermissionTitle: String {
        viewModel.isPlanMode ? "Plan" : Self.permissionTitle(for: viewModel.selectedPermissionProfile)
    }

    private var modelMenu: some View {
        HoverableComposerControl(isEnabled: !viewModel.availableModels.isEmpty) { isHovering in
            Menu {
                ForEach(viewModel.availableModels, id: \.id) { model in
                    Button {
                        setModel(model.id, effort: nil)
                    } label: {
                        SettingsMenuRow(
                            title: model.displayName,
                            isSelected: model.id == viewModel.selectedModel
                        )
                    }
                }
                if let selectedModel, !selectedModel.supportedReasoningEfforts.isEmpty {
                    Divider()
                    Menu("Reasoning Effort") {
                        ForEach(selectedModel.supportedReasoningEfforts, id: \.reasoningEffort) { option in
                            Button {
                                setModel(selectedModel.id, effort: option.reasoningEffort)
                            } label: {
                                SettingsMenuRow(
                                    title: Self.reasoningEffortTitle(option.reasoningEffort),
                                    isSelected: option.reasoningEffort == viewModel.selectedEffort
                                )
                            }
                        }
                    }
                }
            } label: {
                ComposerControlChip(
                    title: modelTitle,
                    detail: selectedEffortTitle,
                    emphasis: .plain,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.availableModels.isEmpty)
            .accessibilityIdentifier("\(accessibilityPrefix).modelMenu")
        }
    }

    private var permissionMenu: some View {
        HoverableComposerControl { isHovering in
            Menu {
                ForEach(
                    composerModeOptions(
                        for: viewModel.agentRef,
                        codexProfileIDs: viewModel.permissionProfiles.map(\.id)
                    ),
                    id: \.self
                ) { option in
                    Button {
                        selectCodexModeOption(option)
                    } label: {
                        SettingsMenuRow(
                            title: option.title,
                            isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile)
                        )
                    }
                    .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
                }
            } label: {
                ComposerControlChip(
                    title: selectedPermissionTitle,
                    detail: nil,
                    emphasis: .pill,
                    layout: layout,
                    isHovering: isHovering
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("\(accessibilityPrefix).permissionMenu")
        }
    }

    // MARK: - Actions

    private func setSpawnModel(_ model: String) {
        Task {
            await viewModel.setSpawnAgentModel(model)
        }
    }

    private func setSpawnPermission(_ value: String?) {
        Task {
            await viewModel.setSpawnAgentPermission(value)
        }
    }

    private func setSpawnEffort(_ effort: String) {
        Task {
            await viewModel.setSpawnAgentEffort(effort)
        }
    }

    private func setModel(_ model: String, effort: String?) {
        Task {
            try? await viewModel.setModel(model: model, effort: effort)
        }
    }

    private func setPermissionProfile(_ id: String) {
        Task {
            try? await viewModel.setPermissionProfile(id: id)
        }
    }

    private func selectCodexModeOption(_ option: ComposerModeOption) {
        let wasPlanMode = viewModel.isPlanMode
        Task {
            if option.isPlan {
                try? await viewModel.setPlanMode(true)
            } else if let value = option.value {
                try? await viewModel.setPermissionProfile(id: value)
                if wasPlanMode {
                    try? await viewModel.setPlanMode(false)
                }
            }
        }
    }

    private func setPlanMode(_ isOn: Bool) {
        Task {
            try? await viewModel.setPlanMode(isOn)
        }
    }

    private func modeOptionIsSelected(_ option: ComposerModeOption, currentValue: String?) -> Bool {
        if option.isPlan {
            return viewModel.isPlanMode
        }
        return !viewModel.isPlanMode && option.value == currentValue
    }

    // MARK: - Labels

    private static let claudeDefaultPermission = "bypassPermissions"

    private static func claudePermissionTitle(for value: String) -> String {
        switch value {
        case "acceptEdits": "Accept Edits"
        case "bypassPermissions": "Bypass"
        default: value
        }
    }

    private static func cursorModeTitle(for value: String?) -> String {
        switch value {
        case "ask": "Ask"
        case .some(let raw): raw
        case nil: "Run Everything"
        }
    }

    private static func spawnEffortTitle(for effort: String) -> String {
        switch effort {
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "XHigh"
        case "max": "Max"
        default: effort
        }
    }

    private static func reasoningEffortTitle(_ effort: String) -> String {
        switch effort {
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "X High"
        default: effort
        }
    }

    private static func permissionTitle(for id: String?) -> String {
        composerPermissionTitle(for: id)
    }
}

private enum ComposerControlFill {
    /// 非ホバー時は背景と同化させる（箱を出さない）。ホバー時のみ視認できる面を出す。
    static let base = Color.clear
    static let hover = DSColor.fillSelected
}

struct HoverableComposerControl<Content: View>: View {
    var isEnabled = true
    @ViewBuilder var content: (Bool) -> Content
    @State private var isHovering = false

    private var isHoveringActive: Bool { isEnabled && isHovering }

    var body: some View {
        content(isHoveringActive)
            // ボタン（ホバー領域）の大きさは Menu の「外側」で確保する。.borderlessButton の Menu は
            // ラベルの frame/padding を無視して内容を詰めて描画するため、チップ側で height/padding を
            // 増やしても箱に効かない。ここ（Menu の外）で padding と minHeight を与えて箱を広げる。
            .padding(.horizontal, DSSpacing.s)
            .frame(minHeight: 34)
            // 背景も Menu の外側に置く（ラベル内側の .background は borderlessButton が描画しないため）。
            .background(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .fill(isHoveringActive ? ComposerControlFill.hover : ComposerControlFill.base)
            )
            .background(
                HoverReporter { hovering in
                    isHovering = hovering
                }
            )
    }
}

/// AppKit の `NSTrackingArea` で hover を検出する。SwiftUI の `.onHover` は
/// `.borderlessButton` の `Menu` を包む View では配送されず発火しないため、tracking area で
/// マウスの出入りを観測する（クリックは奪わない＝Menu の動作と両立する）。
/// mouseEntered/Exited はユーザーイベントなので body 評価中の state 変更は起きない（ADR0010 安全）。
struct HoverReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        HoverTrackingNSView(onChange: onChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HoverTrackingNSView)?.onChange = onChange
    }

    private final class HoverTrackingNSView: NSView {
        var onChange: (Bool) -> Void

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            onChange(true)
        }

        override func mouseExited(with event: NSEvent) {
            onChange(false)
        }
    }
}

struct ComposerAttachPlaceholder: View {
    @Bindable var viewModel: ChatSessionViewModel
    let layout: ComposerSettingsLayout
    let accessibilityIdentifier: String
    @State private var isHovering = false

    private var size: CGFloat {
        layout == .compact ? 24 : 32
    }

    var body: some View {
        Button(action: openAttachmentPanel) {
            Image(systemName: "plus")
                .font(.system(size: layout == .compact ? DSIconSize.s : DSIconSize.m, weight: .medium))
                .foregroundStyle(DSColor.chatTextSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: layout == .compact ? DSRadius.s : DSRadius.m, style: .continuous)
                        .fill(isHovering ? ComposerControlFill.hover : ComposerControlFill.base)
                )
                .contentShape(RoundedRectangle(cornerRadius: layout == .compact ? DSRadius.s : DSRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .help("添付")
    }

    private func openAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if Self.isImage(url) {
                addImage(url)
            } else {
                insertFileReference(url.path)
            }
        }
    }

    private func addImage(_ url: URL) {
        guard ComposerAttachmentCapability.supportsImageAttachments(agentRef: viewModel.agentRef) else {
            insertFileReference(url.path)
            return
        }
        do {
            let data = try Data(contentsOf: url)
            viewModel.attachmentStore.addImage(
                data: data,
                mediaType: Self.mediaType(for: url),
                filename: url.lastPathComponent
            )
        } catch {
            viewModel.attachmentStore.setError("画像を読み込めませんでした: \(url.lastPathComponent)")
        }
    }

    private func insertFileReference(_ path: String) {
        let reference = viewModel.attachmentStore.addFileReference(path: path)
        if viewModel.draft.isEmpty {
            viewModel.draft = reference
        } else if viewModel.draft.last?.isWhitespace == true {
            viewModel.draft += reference
        } else {
            viewModel.draft += " \(reference)"
        }
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static func mediaType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: pathExtension), let mimeType = type.preferredMIMEType {
            return mimeType
        }
        switch pathExtension {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }
}

struct ComposerSettingsOverflowMenu: View {
    @Bindable var viewModel: ChatSessionViewModel
    let workspacePath: String
    let accessibilityIdentifier: String

    var body: some View {
        HoverableComposerControl { isHovering in
            Menu {
                ForEach(composerControls(for: viewModel.agentRef), id: \.self) { kind in
                    overflowMenu(for: kind)
                }
                ComposerOverflowBranchMenu(workspacePath: workspacePath)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: DSIconSize.m, weight: .medium))
                    .foregroundStyle(isHovering ? DSColor.chatTextPrimary : DSColor.chatTextSecondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .help("設定")
    }

    @ViewBuilder
    private func overflowMenu(for kind: ComposerControlKind) -> some View {
        switch kind {
        case .model:
            switch viewModel.agentRef {
            case .builtin(.codex):
                Menu("Model") { codexModelItems }
                    .disabled(viewModel.availableModels.isEmpty)
            default:
                Menu("Model") { spawnModelItems }
                    .disabled(viewModel.availableSpawnAgentModels.isEmpty)
            }
        case .effort:
            if !viewModel.claudeEffortLevels.isEmpty {
                Menu("Effort") { claudeEffortItems }
            }
        case .permission:
            switch viewModel.agentRef {
            case .builtin(.codex):
                Menu("Permission") { codexPermissionItems }
            default:
                Menu("Permission") { spawnPermissionItems }
            }
        case .mode:
            Menu("Mode") { cursorModeItems }
        case .plan:
            EmptyView()
        }
    }

    private var selectedClaudePermission: String {
        viewModel.selectedPermissionProfile ?? "bypassPermissions"
    }

    private var selectedCodexModel: AppServerModel? {
        guard let selected = viewModel.selectedModel else { return nil }
        return viewModel.availableModels.first { $0.id == selected || $0.model == selected }
    }

    private var spawnModelItems: some View {
        ForEach(viewModel.availableSpawnAgentModels, id: \.self) { model in
            Button {
                Task { await viewModel.setSpawnAgentModel(model) }
            } label: {
                SettingsMenuRow(
                    title: viewModel.spawnAgentModelDisplayName(model),
                    isSelected: model == viewModel.selectedModel
                )
            }
        }
    }

    private var claudeEffortItems: some View {
        ForEach(viewModel.claudeEffortLevels, id: \.self) { effort in
            Button {
                Task { await viewModel.setSpawnAgentEffort(effort) }
            } label: {
                SettingsMenuRow(
                    title: Self.spawnEffortTitle(for: effort),
                    isSelected: effort == viewModel.selectedEffort
                )
            }
        }
    }

    private var spawnPermissionItems: some View {
        ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: []), id: \.self) { option in
            Button {
                Task { await viewModel.setSpawnAgentPermission(option.value) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: selectedClaudePermission)
                )
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
        }
    }

    // Cursor の Mode は既定が nil（Run Everything）なので、Claude 用の
    // bypassPermissions フォールバック（selectedClaudePermission）を使わない。
    private var cursorModeItems: some View {
        ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: []), id: \.self) { option in
            Button {
                Task { await viewModel.setSpawnAgentPermission(option.value) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile)
                )
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
        }
    }

    @ViewBuilder
    private var codexModelItems: some View {
        ForEach(viewModel.availableModels, id: \.id) { model in
            Button {
                Task { try? await viewModel.setModel(model: model.id, effort: nil) }
            } label: {
                SettingsMenuRow(
                    title: model.displayName,
                    isSelected: model.id == viewModel.selectedModel
                )
            }
        }
        if let selectedCodexModel, !selectedCodexModel.supportedReasoningEfforts.isEmpty {
            Divider()
            Menu("Reasoning Effort") {
                ForEach(selectedCodexModel.supportedReasoningEfforts, id: \.reasoningEffort) { option in
                    Button {
                        Task {
                            try? await viewModel.setModel(
                                model: selectedCodexModel.id,
                                effort: option.reasoningEffort
                            )
                        }
                    } label: {
                        SettingsMenuRow(
                            title: Self.reasoningEffortTitle(option.reasoningEffort),
                            isSelected: option.reasoningEffort == viewModel.selectedEffort
                        )
                    }
                }
            }
        }
    }

    private var codexPermissionItems: some View {
        ForEach(
            composerModeOptions(
                for: viewModel.agentRef,
                codexProfileIDs: viewModel.permissionProfiles.map(\.id)
            ),
            id: \.self
        ) { option in
            Button {
                Task { await selectCodexModeOption(option) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile)
                )
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
        }
    }

    private func selectCodexModeOption(_ option: ComposerModeOption) async {
        let wasPlanMode = viewModel.isPlanMode
        if option.isPlan {
            try? await viewModel.setPlanMode(true)
        } else if let value = option.value {
            try? await viewModel.setPermissionProfile(id: value)
            if wasPlanMode {
                try? await viewModel.setPlanMode(false)
            }
        }
    }

    private func modeOptionIsSelected(_ option: ComposerModeOption, currentValue: String?) -> Bool {
        if option.isPlan {
            return viewModel.isPlanMode
        }
        return !viewModel.isPlanMode && option.value == currentValue
    }

    private static func spawnEffortTitle(for effort: String) -> String {
        switch effort {
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "XHigh"
        case "max": "Max"
        default: effort
        }
    }

    private static func reasoningEffortTitle(_ effort: String) -> String {
        switch effort {
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "X High"
        default: effort
        }
    }
}

private struct ComposerOverflowBranchMenu: View {
    let workspacePath: String
    @State private var currentBranch: String?
    @State private var branches: [String] = []
    @State private var errorMessage: String?
    @State private var isCheckingOut = false

    var body: some View {
        let expanded = (workspacePath as NSString).expandingTildeInPath
        if !expanded.isEmpty {
            Menu(branchTitle) {
                if let errorMessage {
                    Text(errorMessage)
                }
                Button("Refresh") {
                    refreshBranches(at: expanded)
                }
                Divider()
                ForEach(branches, id: \.self) { branch in
                    Button {
                        checkout(branch, at: expanded)
                    } label: {
                        SettingsMenuRow(
                            title: branch,
                            isSelected: branch == currentBranch
                        )
                    }
                    .disabled(isCheckingOut || branch == currentBranch)
                }
            }
            .task(id: expanded) {
                refreshBranches(at: expanded)
            }
        }
    }

    private var branchTitle: String {
        if isCheckingOut { return "Branch: switching..." }
        if let currentBranch { return "Branch: \(currentBranch)" }
        return "Branch"
    }

    private func refreshBranches(at path: String) {
        currentBranch = GitBranchReader.currentBranch(at: path)
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try GitBranchSwitcher.localBranches(at: path)
                }.value
                branches = loaded
                errorMessage = nil
            } catch {
                branches = []
                errorMessage = shortErrorMessage(from: error)
            }
        }
    }

    private func checkout(_ branch: String, at path: String) {
        guard branch != currentBranch, !isCheckingOut else { return }
        isCheckingOut = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try GitBranchSwitcher.checkout(branch: branch, at: path)
                }.value
                currentBranch = branch
                errorMessage = nil
                refreshBranches(at: path)
            } catch {
                currentBranch = GitBranchReader.currentBranch(at: path)
                errorMessage = shortErrorMessage(from: error)
            }
            isCheckingOut = false
        }
    }

    private func shortErrorMessage(from error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return String(describing: error) }
        return message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
    }
}

enum ComposerControlEmphasis {
    case plain
    case pill
}

struct ComposerControlChip: View {
    let title: String
    let detail: String?
    var systemImage: String? = nil
    var emphasis: ComposerControlEmphasis = .pill
    var isActive = false
    var layout: ComposerSettingsLayout = .standard
    var isHovering = false

    private var chipHeight: CGFloat {
        // standard 28: 入力欄パネル全体≈80px の要件（ADR 0046）に合わせフッターを圧縮
        layout == .compact ? 24 : 28
    }

    private var maxChipWidth: CGFloat {
        layout == .compact ? 100 : 220
    }

    private var horizontalPadding: CGFloat {
        layout == .compact ? DSSpacing.xs : DSSpacing.m
    }

    /// 入力欄のプレースホルダー程度に控えめな色へ寄せる。
    private var inactiveForeground: Color {
        DSColor.textTertiary
    }

    private var foregroundColor: Color {
        isActive ? DSColor.chatAccent : inactiveForeground
    }

    private var pillFill: Color {
        if isActive {
            return DSColor.chatAccent.opacity(0.16)
        }
        return isHovering ? ComposerControlFill.hover : ComposerControlFill.base
    }

    var body: some View {
        let label = HStack(spacing: DSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: layout == .compact ? DSIconSize.s : DSIconSize.m, weight: .medium))
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            if let detail {
                Text(detail)
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
            }
        }
        .font(chipFont)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .frame(height: chipHeight)
        .frame(maxWidth: maxChipWidth)

        // 背景は HoverableComposerControl（Menu の外側）が描く。ここ（Menu のラベル内側）に
        // 背景を置いても .borderlessButton では描画されないため、ラベルは中身のみ返す。
        label
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
    }

    private var chipFont: Font {
        if layout == .compact || !isActive {
            return DSFont.caption
        }
        return DSFont.captionStrong
    }
}

struct SettingsMenuRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}
