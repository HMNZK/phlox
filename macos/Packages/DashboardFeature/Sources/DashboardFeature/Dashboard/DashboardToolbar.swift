import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// ツールバーの幅の段階（01 D の表）。
enum ToolbarDensity: Equatable {
/// 1280pt 以上。表示モードの名称を表示する。
    case full
/// 960–1279pt。表示モードの名称を表示する。
    case compact
/// 960pt 未満。表示モードはアイコンだけ。
    case minimal

    static func forWindowWidth(_ width: CGFloat) -> ToolbarDensity {
        if width >= 1280 { return .full }
        if width >= 960 { return .compact }
        return .minimal
    }
}
/// 信号と同じ標準タイトルバーに置く操作。縦位置はシステムが揃える。
struct DashboardToolbar: ToolbarContent {
    @Environment(\.localizationBundle) private var localizationBundle
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let changeCount: Int
    let bottomPanel: BottomPanelState
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            items.sharedBackgroundVisibility(.hidden)
        } else {
            items
        }
    }

    @ToolbarContentBuilder
    private var items: some ToolbarContent {
        // 開閉は常に出し、その右に選択中のタブの名前を出す（新規チャットの要件 FR-40・FR-41）。
        ToolbarItem(id: "dashboard-sidebar", placement: .navigation) {
            HStack(spacing: DSSpacing.s) {
                SidebarToggleButton(router: router, attentionCount: viewModel.attentionEntries.count)
                HeaderTabTitle(viewModel: viewModel, router: router, changeCount: changeCount)
            }
        }
        ToolbarItem(placement: .automatic) { Spacer() }
        ToolbarItem(id: "dashboard-display", placement: .primaryAction) {
            ViewModeToggle(mode: $router.viewMode)
        }
        ToolbarItem(id: "dashboard-bottom-panel", placement: .primaryAction) {
            bottomPanelToggleButton
        }
        ToolbarItem(id: "dashboard-inspector", placement: .primaryAction) {
            inspectorToggleButton
        }
    }

    private var inspectorToggleButton: some View {
        Button {
            // 動きは DashboardView の dsPaneAnimation でサイドバーと揃える。
            router.toggleInspector()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(router.inspectorVisible ? DSColor.textPrimary : DSColor.textSecondary)
                .frame(width: DSLayout.toolbarIconButtonSize, height: DSLayout.toolbarIconButtonSize)
                .background(
                    router.inspectorVisible ? DSColor.fillSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: DSRadius.row)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text("インスペクタ（⌃⌘I）", bundle: localizationBundle))
        .accessibilityLabel(Text("インスペクタ（⌃⌘I）", bundle: localizationBundle))
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { router.inspectorVisible }, set: { value in
                if value != router.inspectorVisible { router.toggleInspector() }
            })) { Text("インスペクタ（⌃⌘I）", bundle: localizationBundle) }
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("inspector-toggle")
        }
        .accessibilityIdentifier("inspector-toggle")
    }

    private var bottomPanelToggleButton: some View {
        BottomPanelToggleButton(state: bottomPanel, projectID: BottomPanelState.targetProjectID(
            mode: router.viewMode, selectedProjectID: router.selectedProjectID,
            selectedTileProjectID: router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID }))
    }
}

private struct BottomPanelToggleButton: View {
    @Environment(\.localizationBundle) private var localizationBundle
    let state: BottomPanelState
    let projectID: ProjectID?

    var body: some View {
        Button { state.toggle(projectID: projectID) } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(state.isVisible ? DSColor.textPrimary : DSColor.textSecondary)
                .frame(width: DSLayout.toolbarIconButtonSize, height: DSLayout.toolbarIconButtonSize)
                .background(state.isVisible ? DSColor.fillSelected : Color.clear,
                            in: RoundedRectangle(cornerRadius: DSRadius.row))
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .disabled(projectID == nil)
        .help(Text(LocalizedStringKey(state.isVisible ? "下部パネルを隠す（⌘J）" : "下部パネルを表示（⌘J）"), bundle: localizationBundle))
        .accessibilityLabel(Text("下部パネル（⌘J）", bundle: localizationBundle))
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { state.isVisible }, set: { value in
                if value != state.isVisible { state.toggle(projectID: projectID) }
            })) { Text("下部パネル（⌘J）", bundle: localizationBundle) }
                .toggleStyle(.checkbox)
                .disabled(projectID == nil)
                .accessibilityIdentifier("bottom-panel-toggle")
        }
        .accessibilityIdentifier("bottom-panel-toggle")
    }
}

/// ヘッダーに出す選択中のタブの名前（新規チャットの要件 FR-41）。文字は子タブの列と同じ。
struct HeaderTabTitle: View {
    let viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let changeCount: Int
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    /// 新規チャット画面は `.newChat`。グリッドとプロジェクトが無いときは出さない。
    static func tab(router: AppRouter, viewModel: DashboardViewModel) -> ProjectTab? {
        guard router.viewMode == .single, !viewModel.projects.isEmpty else { return nil }
        if router.showsNewChat { return .newChat }
        let projectID = router.selectedProjectID ?? router.selectedSession.flatMap { viewModel.sessionNode(id: $0)?.projectID }
        guard let projectID else { return router.selectedSession.map(ProjectTab.chat) ?? .newChat }
        return router.tabs.layout(for: projectID).selected ?? router.selectedSession.map(ProjectTab.chat) ?? .newChat
    }

    var body: some View {
        if let tab = Self.tab(router: router, viewModel: viewModel) {
            Text(verbatim: ChildTabBar.titleText(for: tab, viewModel: viewModel, changeCount: changeCount,
                                                 locale: locale, bundle: localizationBundle))
                .font(DSFont.sessionTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 360, alignment: .leading)
                .accessibilityIdentifier("header-tab-title")
        }
    }
}

/// サイドバー開閉。ヘッダーの左端に常に出す（新規チャットの要件 FR-40）。
/// 隠しているときは対応待ちの件数を添える（01 D3）。
struct SidebarToggleButton: View {
    @Bindable var router: AppRouter
    var attentionCount: Int = 0

    private var isShowing: Bool {
        router.sidebarVisible && (!router.sidebarLacksRoom || router.sidebarPeeking)
    }

    var body: some View {
        Button {
            router.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: DSLayout.toolbarIconButtonSize, height: DSLayout.toolbarIconButtonSize)
                .overlay(alignment: .topTrailing) {
                    if !isShowing, attentionCount > 0 {
                        CountBadge(count: attentionCount)
                            .offset(x: 6, y: -4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .modifier(FirstClickActivates())
        .help(isShowing ? Text("サイドバーを隠す（⌃⌘S）") : Text("サイドバーを表示（⌃⌘S）"))
        .accessibilityLabel(isShowing ? Text("サイドバーを隠す（⌃⌘S）") : Text("サイドバーを表示（⌃⌘S）"))
    }
}

/// 窓が前面でないときの最初のクリックでも押せるようにする（macOS 15 以降）。
/// タイトルバーの帯のボタンは、既定では最初のクリックが窓を前に出すだけで終わり「押せない」ように見える。
private struct FirstClickActivates: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.allowsWindowActivationEvents(true)
        } else {
            content
        }
    }
}

/// 件数を中立色の面と主文字色で表示する。
struct CountBadge: View {
    let count: Int

    var body: some View {
        // PhloxWindow.dc.html:149: 最小 18×16、角丸 8、白 11/700。
        Text("\(count)")
            .font(DSFont.meta.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(DSColor.textPrimary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(DSColor.controlBackground, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

/// 単体/グリッドの 2 セグメント。淡いトラックの上で、選択セグメントだけを面で示す。
struct ViewModeToggle: View {
    @Binding var mode: ViewMode
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            segment(.single, symbol: "square", title: AppLocalizedString.string("単体", locale: locale), key: "⌃⌘1")
            segment(.grid, symbol: "square.grid.2x2", title: AppLocalizedString.string("グリッド", locale: locale), key: "⌃⌘2")
        }
        .padding(.horizontal, DSSpacing.xxs)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("表示モード"))
    }

    private func segment(_ value: ViewMode, symbol: String, title: String, key: String) -> some View {
        ModeSegmentButton(
            identifier: "view-mode-\(value.rawValue)",
            symbol: symbol,
            title: nil,
            help: String(format: AppLocalizedString.string("%@（%@）", locale: locale), title, key),
            isOn: mode == value,
            action: { mode = value }
        )
    }
}

private struct ModeSegmentButton: View {
    let identifier: String
    let symbol: String
    let title: String?
    let help: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: DSIconSize.modeSegment, weight: .medium))
                if let title {
                    Text(title)
                        .font(DSFont.auxiliary.weight(.medium))
                }
            }
            .padding(.horizontal, title == nil ? 0 : 10)
            // 見本のトラック高 24、内側の面は 20。押せる範囲は 24 を保つ。
            .frame(minWidth: DSHitTarget.modeSegmentWidth, minHeight: DSLayout.modeSegmentFaceHeight)
            .background(
                isOn ? DSColor.controlBackground : (hovering ? DSColor.fillSubtle : Color.clear),
                in: RoundedRectangle(cornerRadius: DSRadius.s)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.s)
                    .strokeBorder(isOn ? DSColor.controlBorder : .clear, lineWidth: DSLayout.controlBorderWidth)
            }
            .frame(minHeight: DSHitTarget.modeSegmentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? DSColor.textPrimary : DSColor.textSecondary)
        .onHover { hovering = $0 }
        .pointingHandCursor()
        .help(help)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
