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
    let explanation: String
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

func composerModeOptions(for agentRef: AgentRef, codexProfileIDs: [String], languageCode: String = "en") -> [ComposerModeOption] {
    switch agentRef {
    case .builtin(.codex):
        codexProfileIDs.map {
            let w = UIWording.permission(agent: .codex, kind: .codexProfile, value: $0, languageCode: languageCode)
            return ComposerModeOption(value: $0, title: w.title, explanation: w.explanation, isPlan: false)
        } + [
            ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .codex, kind: .codexProfile, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
    case .builtin(.claudeCode):
        [
            ComposerModeOption(value: "acceptEdits", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "acceptEdits", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "auto", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "auto", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "bypassPermissions", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "bypassPermissions", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "manual", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "manual", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "manual", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "dontAsk", title: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).title, explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "dontAsk", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
    case .builtin(.cursor):
        [
            ComposerModeOption(value: nil, title: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: nil, languageCode: languageCode).title, explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: nil, languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "ask", title: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "ask", languageCode: languageCode).title, explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "ask", languageCode: languageCode).explanation, isPlan: false),
            ComposerModeOption(value: "plan", title: UIWording.text(.planOption, languageCode: languageCode), explanation: UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: "plan", languageCode: languageCode).explanation, isPlan: true),
        ]
    default:
        []
    }
}

func composerPermissionTitle(for id: String?, languageCode: String = "en") -> String {
    UIWording.permission(agent: .codex, kind: .codexProfile, value: id, languageCode: languageCode).title
}

enum ComposerControlSide {
    case leading
    case trailing
}

/// フッター左右分割の単一真実源。PhloxReply.dc.html では設定のチップはすべて左（＋ モデル effort 権限）、
/// 右はブランチ・コンテキスト・送信だけ。
func composerControls(for agentRef: AgentRef, side: ComposerControlSide) -> [ComposerControlKind] {
    switch side {
    case .leading:
        return composerControls(for: agentRef)
    case .trailing:
        return []
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
    @Environment(\.locale) private var locale
    @State private var openMenu: OpenMenu?
    @State private var modelSearch = ""
    @State private var lastNonPlanPermission: String?

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

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
            HStack(spacing: 6) {
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
        let isCursor = viewModel.agentRef == .builtin(.cursor)
        let title = viewModel.selectedModel.map(viewModel.spawnAgentModelDisplayName) ?? UIWording.text(.modelLabel, languageCode: languageCode)
        return Button { toggle(.model) } label: {
            ComposerChipLabel(title: title, isOpen: openMenu == .model)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: AppLocalizedString.string("モデル", locale: locale) + ": " + title))
        .accessibilityIdentifier("\(accessibilityPrefix).spawnModelMenu")
        .disabled(viewModel.availableSpawnAgentModels.isEmpty)
        .composerPopup(isPresented: binding(for: .model)) {
            ComposerPopupSurface(width: 260) {
                ComposerMenuList(
                    search: isCursor ? $modelSearch : nil,
                    searchPlaceholder: String(
                        format: AppLocalizedString.string("モデルを検索（%lld）", locale: locale),
                        viewModel.availableSpawnAgentModels.count
                    ),
                    sections: [ComposerMenuSection(id: "models", rows: filteredSpawnModels.map { model in
                        ComposerMenuRow(
                            id: model,
                            title: viewModel.spawnAgentModelDisplayName(model),
                            isSelected: model == viewModel.selectedModel,
                            action: { setSpawnModel(model) }
                        )
                    })],
                    onClose: closeMenu
                ) {
                    // CLI から一覧を取れず内蔵の一覧を出しているとき（05 O3）。
                    if viewModel.isUsingBuiltinModelList {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("CLI からモデル一覧を取得できませんでした。内蔵の一覧を表示しています。")
                                .foregroundStyle(DSColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("再試行") {
                                Task { await viewModel.retryModelListFetch() }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DSColor.accentInk)
                        }
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(DSColor.attentionTint(.approval), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, 3)
                        .padding(.top, 5)
                        .padding(.bottom, 2)
                    }
                }
            }
        }
    }

    private var filteredSpawnModels: [String] {
        let query = modelSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return viewModel.availableSpawnAgentModels }
        return viewModel.availableSpawnAgentModels.filter {
            $0.lowercased().contains(query) || viewModel.spawnAgentModelDisplayName($0).lowercased().contains(query)
        }
    }

    private var claudeEffortMenu: some View {
        let title = "effort: " + (viewModel.selectedEffort ?? UIWording.text(.reasoningEffortLabel, languageCode: languageCode))
        return Button { toggle(.effort) } label: {
            ComposerChipLabel(title: title, isOpen: openMenu == .effort)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier("\(accessibilityPrefix).claudeEffortMenu")
        .composerPopup(isPresented: binding(for: .effort)) {
            ComposerPopupSurface(width: 150) {
                ComposerMenuList(
                    sections: [ComposerMenuSection(id: "efforts", rows: viewModel.claudeEffortLevels.map { effort in
                        ComposerMenuRow(
                            id: effort,
                            title: effort,
                            isSelected: effort == viewModel.selectedEffort,
                            action: { setSpawnEffort(effort) }
                        )
                    })],
                    onClose: closeMenu
                )
            }
        }
    }

    private var claudePermissionMenu: some View {
        let options = composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode)
        let title = permissionChipTitle(viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .claude, kind: .claudePermissionMode, value: selectedClaudePermission, languageCode: languageCode).title)
        return permissionChip(
            title: title,
            panelTitle: AppLocalizedString.string("権限モード", locale: locale),
            agentName: "Claude Code",
            options: options,
            currentValue: selectedClaudePermission,
            footnote: AppLocalizedString.string("許可・確認・拒否のルールは エージェント管理 > パーミッション", locale: locale),
            onSelect: { setSpawnPermission($0.value) },
            onPlanChange: { isOn in
                // Plan のまま開いたときは前のモードが分からないので、毎回確認する manual に戻す（強い権限へは戻さない）。
                setSpawnPermission(isOn ? options.first(where: \.isPlan)?.value : (lastNonPlanPermission ?? "manual"))
            },
            accessibilityIdentifier: "\(accessibilityPrefix).claudePermissionMenu"
        )
    }

    private var cursorModeMenu: some View {
        let options = composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode)
        let title = permissionChipTitle(viewModel.isPlanMode ? UIWording.text(.planOption, languageCode: languageCode) : UIWording.permission(agent: .cursor, kind: .cursorOperationMode, value: viewModel.selectedPermissionProfile, languageCode: languageCode).title)
        return permissionChip(
            title: title,
            panelTitle: AppLocalizedString.string("権限", locale: locale),
            agentName: "Cursor",
            options: options,
            currentValue: viewModel.selectedPermissionProfile,
            footnote: AppLocalizedString.string("許可・拒否のルールは エージェント管理 > パーミッション", locale: locale),
            onSelect: { setSpawnPermission($0.value) },
            onPlanChange: { isOn in
                setSpawnPermission(isOn ? options.first(where: \.isPlan)?.value : lastNonPlanPermission)
            },
            accessibilityIdentifier: "\(accessibilityPrefix).cursorModeMenu"
        )
    }

    /// 権限のチップと箱（05 O4〜O6）。Plan はラジオではなく下のスイッチで切り替える。
    private func permissionChip(
        title: String,
        panelTitle: String,
        agentName: String,
        options: [ComposerModeOption],
        currentValue: String?,
        footnote: String,
        onSelect: @escaping (ComposerModeOption) -> Void,
        onPlanChange: @escaping (Bool) -> Void,
        accessibilityIdentifier: String
    ) -> some View {
        let choices = options.filter { !$0.isPlan }
        return Button { toggle(.permission) } label: {
            ComposerChipLabel(title: title, isOpen: openMenu == .permission)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier(accessibilityIdentifier)
        .composerPopup(isPresented: binding(for: .permission)) {
            ComposerPopupSurface(width: 340, cornerRadius: 10, padding: 10) {
                ComposerPermissionPanel(
                    title: panelTitle,
                    subtitle: String(format: AppLocalizedString.string("%@ · %lld 種", locale: locale), agentName, choices.count),
                    options: choices,
                    isSelected: { modeOptionIsSelected($0, currentValue: currentValue) },
                    isPlanOn: viewModel.isPlanMode,
                    isPlanAvailable: viewModel.isPlanModeAvailable,
                    footnote: footnote,
                    onSelect: { option in
                        lastNonPlanPermission = option.value
                        onSelect(option)
                    },
                    onPlanChange: onPlanChange,
                    onClose: closeMenu
                )
            }
        }
        // 読み込み前の nil（チップが既定値で代わりに出しているだけ）は前のモードとして覚えない。
        .onChange(of: viewModel.selectedPermissionProfile, initial: true) { _, value in
            if let value, value != "plan", !viewModel.isPlanMode { lastNonPlanPermission = value }
        }
    }

    private var selectedClaudePermission: String {
        viewModel.selectedPermissionProfile ?? Self.claudeDefaultPermission
    }

    /// 「権限: 標準」（05 O4〜O6）。
    private func permissionChipTitle(_ value: String) -> String {
        AppLocalizedString.string("権限", locale: locale) + ": " + value
    }

    // MARK: - Codex app-server menus

    private var selectedModel: AppServerModel? {
        guard let selected = viewModel.selectedModel else { return nil }
        return viewModel.availableModels.first { $0.id == selected || $0.model == selected }
    }

    private var modelTitle: String {
        selectedModel?.displayName ?? viewModel.selectedModel ?? UIWording.text(.modelLabel, languageCode: languageCode)
    }

    private var selectedPermissionTitle: String {
        if viewModel.isPlanMode {
            UIWording.text(.planOption, languageCode: languageCode)
        } else if viewModel.selectedPermissionProfile == nil {
            AppLocalizedString.string("未設定", locale: locale)
        } else {
            UIWording.permission(agent: .codex, kind: .codexProfile, value: viewModel.selectedPermissionProfile, languageCode: languageCode).title
        }
    }

    /// Codex のモデル（「gpt-6-sol · high」）。推論の深さは横に出る子の箱で選ぶ（05 O2）。
    private var modelMenu: some View {
        let title = [modelTitle, viewModel.selectedEffort].compactMap { $0 }.joined(separator: " · ")
        return Button { toggle(.model) } label: {
            ComposerChipLabel(title: title, isOpen: openMenu == .model)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: AppLocalizedString.string("モデル", locale: locale) + ": " + title))
        .accessibilityIdentifier("\(accessibilityPrefix).modelMenu")
        .disabled(viewModel.availableModels.isEmpty)
        .composerPopup(isPresented: binding(for: .model), relaysHorizontalKeys: codexEffortSection != nil) {
            ComposerMenuWithSideList(
                title: AppLocalizedString.string("モデル", locale: locale),
                sections: [codexModelSection],
                sideTitle: UIWording.text(.reasoningEffortLabel, languageCode: languageCode),
                sideSection: codexEffortSection,
                onClose: closeMenu
            )
        }
    }

    private var codexModelSection: ComposerMenuSection {
        ComposerMenuSection(id: "models", rows: viewModel.availableModels.map { model in
            ComposerMenuRow(
                id: model.id,
                title: model.displayName,
                isSelected: model.id == viewModel.selectedModel,
                action: { setModel(model.id, effort: nil) }
            )
        })
    }

    private var codexEffortSection: ComposerMenuSection? {
        guard let selectedModel, !selectedModel.supportedReasoningEfforts.isEmpty else { return nil }
        return ComposerMenuSection(
            id: "efforts",
            rows: selectedModel.supportedReasoningEfforts.map { option in
                ComposerMenuRow(
                    id: "effort-\(option.reasoningEffort)",
                    title: option.reasoningEffort,
                    isSelected: option.reasoningEffort == viewModel.selectedEffort,
                    action: { setModel(selectedModel.id, effort: option.reasoningEffort) }
                )
            }
        )
    }

    private var permissionMenu: some View {
        let options = composerModeOptions(
            for: viewModel.agentRef,
            codexProfileIDs: viewModel.permissionProfiles.map(\.id),
            languageCode: languageCode
        )
        return permissionChip(
            title: permissionChipTitle(selectedPermissionTitle),
            panelTitle: AppLocalizedString.string("承認とサンドボックス", locale: locale),
            agentName: "Codex",
            options: options,
            currentValue: viewModel.selectedPermissionProfile,
            footnote: AppLocalizedString.string("このセッションだけに効く。既定は エージェント管理 > 設定", locale: locale),
            onSelect: { selectCodexModeOption($0) },
            onPlanChange: { setPlanMode($0) },
            accessibilityIdentifier: "\(accessibilityPrefix).permissionMenu"
        )
    }

    // MARK: - Open state

    private enum OpenMenu { case model, effort, permission }

    private func toggle(_ menu: OpenMenu) {
        modelSearch = ""
        openMenu = openMenu == menu ? nil : menu
    }

    private func closeMenu() { openMenu = nil }

    private func binding(for menu: OpenMenu) -> Binding<Bool> {
        Binding(get: { openMenu == menu }, set: { if !$0, openMenu == menu { openMenu = nil } })
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
    @Environment(\.locale) private var locale

    var body: some View {
        // PhloxReply.dc.html の plus: 24×24・角丸 6・「＋」15・fg2・面なし（ポインタを置くとホバーの面）。
        Button(action: openAttachmentPanel) {
            Text(verbatim: "＋")
                .font(.system(size: 15))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? DSColor.fillSubtle : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(Text(attachLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(Text(attachLabel))
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

    /// 画像を送れないエージェントでは「参照として挿入」（PhloxReply.dc.html の plusAria）。
    /// Codex の画像非対応モデルは画像も添付する（送るときに止める）ので「添付」のまま。
    private var attachLabel: LocalizedStringKey {
        viewModel.imageAttachmentSupport == .agentUnsupported ? "ファイルを参照として挿入" : "ファイルや画像を添付"
    }

    private func addImage(_ url: URL) {
        guard viewModel.imageAttachmentSupport != .agentUnsupported else {
            insertFileReference(url.path)
            viewModel.attachmentStore.setError(
                ComposerAttachmentCapability.fileReferenceNotice(agentRef: viewModel.agentRef, locale: locale),
                tone: .neutral
            )
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let attachment = viewModel.attachmentStore.addImage(
                data: data,
                mediaType: Self.mediaType(for: url),
                filename: url.lastPathComponent
            ) {
                let applied = ComposerImagePlaceholder.inserting(
                    number: attachment.number,
                    into: viewModel.draft,
                    cursorUTF16: viewModel.draft.utf16.count
                )
                viewModel.draft = applied.text
            }
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
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

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
                Menu(UIWording.text(.modelLabel, languageCode: languageCode)) { codexModelItems }
                    .disabled(viewModel.availableModels.isEmpty)
            default:
                Menu(UIWording.text(.modelLabel, languageCode: languageCode)) { spawnModelItems }
                    .disabled(viewModel.availableSpawnAgentModels.isEmpty)
            }
        case .effort:
            if !viewModel.claudeEffortLevels.isEmpty {
                Menu(UIWording.text(.reasoningEffortLabel, languageCode: languageCode)) { claudeEffortItems }
            }
        case .permission:
            switch viewModel.agentRef {
            case .builtin(.codex):
                Menu(AppLocalizedString.string("権限", locale: locale)) { codexPermissionItems }
            default:
                Menu(AppLocalizedString.string("権限", locale: locale)) { spawnPermissionItems }
            }
        case .mode:
            Menu(UIWording.text(.modeLabel, languageCode: languageCode)) { cursorModeItems }
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
                    title: Self.spawnEffortTitle(for: effort, languageCode: languageCode),
                    isSelected: effort == viewModel.selectedEffort
                )
            }
        }
    }

    private var spawnPermissionItems: some View {
        ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \.self) { option in
            Button {
                Task { await viewModel.setSpawnAgentPermission(option.value) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: selectedClaudePermission),
                    explanation: option.explanation
                )
            }
            .disabled(option.isPlan && !viewModel.isPlanModeAvailable)
        }
    }

    // Cursor の Mode は既定が nil（Agent）なので、Claude 用の
    // bypassPermissions フォールバック（selectedClaudePermission）を使わない。
    private var cursorModeItems: some View {
        ForEach(composerModeOptions(for: viewModel.agentRef, codexProfileIDs: [], languageCode: languageCode), id: \.self) { option in
            Button {
                Task { await viewModel.setSpawnAgentPermission(option.value) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile),
                    explanation: option.explanation
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
            Menu(UIWording.text(.reasoningEffortLabel, languageCode: languageCode)) {
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
                            title: Self.reasoningEffortTitle(option.reasoningEffort, languageCode: languageCode),
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
                codexProfileIDs: viewModel.permissionProfiles.map(\.id),
                languageCode: languageCode
            ),
            id: \.self
        ) { option in
            Button {
                Task { await selectCodexModeOption(option) }
            } label: {
                SettingsMenuRow(
                    title: option.title,
                    isSelected: modeOptionIsSelected(option, currentValue: viewModel.selectedPermissionProfile),
                    explanation: option.explanation
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

    private static func spawnEffortTitle(for effort: String, languageCode: String) -> String {
        switch effort {
        case "low": UIWording.text(.effortLow, languageCode: languageCode)
        case "medium": UIWording.text(.effortMedium, languageCode: languageCode)
        case "high": UIWording.text(.effortHigh, languageCode: languageCode)
        case "xhigh": UIWording.text(.effortXHigh, languageCode: languageCode)
        case "max": UIWording.text(.effortMax, languageCode: languageCode)
        default: effort
        }
    }

    private static func reasoningEffortTitle(_ effort: String, languageCode: String) -> String {
        switch effort {
        case "low": UIWording.text(.effortLow, languageCode: languageCode)
        case "medium": UIWording.text(.effortMedium, languageCode: languageCode)
        case "high": UIWording.text(.effortHigh, languageCode: languageCode)
        case "xhigh": UIWording.text(.effortXHigh, languageCode: languageCode)
        default: effort
        }
    }
}

private struct ComposerOverflowBranchMenu: View {
    let workspacePath: String
    @Environment(\.locale) private var locale
    @State private var currentBranch: String?
    @State private var branches: [String] = []
    @State private var errorMessage: String?
    @State private var isCheckingOut = false

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    var body: some View {
        let expanded = (workspacePath as NSString).expandingTildeInPath
        if !expanded.isEmpty {
            Menu(branchTitle) {
                if let errorMessage {
                    Text(errorMessage)
                }
                Button(UIWording.text(.refreshAction, languageCode: languageCode)) {
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
        return UIWording.text(.missingBranch, languageCode: languageCode)
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
    let detail: String?
    let explanation: String?

    init(title: String, isSelected: Bool, detail: String? = nil, explanation: String? = nil) {
        self.title = title
        self.isSelected = isSelected
        self.detail = detail
        self.explanation = explanation
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                if let text = explanation ?? detail {
                    Text(text)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.chatTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}

/// 入力欄の ⇧Tab: 推論の深さを次の段へ回し、変えた段を読み上げる。回せないときは false（入力欄の既定の動きに任せる）。
@MainActor
enum ComposerEffortCycle {
    static func perform(_ viewModel: ChatSessionViewModel, locale: Locale) -> Bool {
        guard viewModel.cyclableEfforts.count > 1 else { return false }
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        Task {
            guard let effort = await viewModel.cycleEffort() else {
                guard !viewModel.isTerminating else { return }
                // キーは受けたので、変えられなかったことを伝える（Codex の設定の更新に失敗したときなど）。
                NSSound.beep()
                AccessibilityNotification.Announcement(AppLocalizedString.string("推論の深さを変えられませんでした", locale: locale)).post()
                return
            }
            // チップと同じく段の名前（high など）で、画面にいま出ている段を読む（待つ間にメニューで選び直していればそちら）。
            AccessibilityNotification.Announcement("\(UIWording.text(.reasoningEffortLabel, languageCode: languageCode)) \(viewModel.selectedEffort ?? effort)").post()
        }
        return true
    }
}
