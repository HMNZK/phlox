import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// ツールバーの幅の段階（01 D の表）。
enum ToolbarDensity: Equatable {
    /// 1280pt 以上。全要素、使用量はゲージ。
    case full
    /// 960–1279pt。worktree はアイコンだけ、使用量は文字。
    case compact
    /// 960pt 未満。表示モードはアイコンだけ、使用量は最小の残量 1 つ、対応待ちは件数だけ。
    case minimal

    static func forWindowWidth(_ width: CGFloat) -> ToolbarDensity {
        if width >= 1280 { return .full }
        if width >= 960 { return .compact }
        return .minimal
    }
}

/// 中央と右インスペクタの上に渡る 52pt のツールバー（01 A1）。単体とグリッドで並びを変えない。
/// 左: （サイドバーを隠しているとき）信号の右にサイドバー開閉 → タイトルとサブタイトル → worktree 隔離。
/// 中央: 表示モード。右: 対応待ち → 使用量 → インスペクタ開閉。
struct DashboardToolbar: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var usageMonitor: UsageMonitor
    let density: ToolbarDensity
    /// サイドバーが見えていないとき、信号の右にサイドバー開閉を出す。
    let showsSidebarToggle: Bool

    @AppStorage(UsageSettings.showInHeaderKey) private var showUsageInHeader = true
    @AppStorage(UsageSettings.showUnavailableKey) private var showUnavailable = false
    @Environment(\.locale) private var locale

    /// 信号（閉じる・しまう・拡大）が占める幅。
    private static let trafficLightsWidth: CGFloat = 70

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            if showsSidebarToggle {
                Color.clear.frame(width: Self.trafficLightsWidth, height: 1)
                SidebarToggleButton(router: router, attentionCount: viewModel.attentionEntries.count)
            }
            titleBlock
            worktreeMenu
            Spacer(minLength: DSSpacing.s)
            ViewModeToggle(mode: $router.viewMode, showsText: density != .minimal)
            Spacer(minLength: DSSpacing.s)
            AttentionButton(viewModel: viewModel, router: router, density: density)
            if showUsageInHeader, !UsageDisplay.topBarChips(usages: usageMonitor.usages, showUnavailable: showUnavailable, now: Date()).isEmpty {
                usageChip
            }
            Rectangle()
                .fill(DSColor.separator)
                .frame(width: 1, height: 18)
                .padding(.horizontal, DSSpacing.xxs)
            inspectorToggleButton
        }
        // PhloxWindow.dc.html: padding 0 10 0 14、gap 8。
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: DSLayout.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(DSColor.toolbarBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("ツールバー"))
    }

    private var selectedNode: SessionNode? {
        router.selectedSession.flatMap { viewModel.sessionNode(id: $0) }
    }

    private var selectedProject: Project? {
        guard let projectID = router.selectedProjectID else { return nil }
        return viewModel.projects.first(where: { $0.id == projectID })
    }

    // MARK: - タイトル

    @ViewBuilder
    private var titleBlock: some View {
        if let node = selectedNode {
            let presentation = SessionTitlePresentation(
                state: node.titleState,
                fallback: SessionViewModel.shortID(for: node.id),
                workspacePath: node.workspacePath
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.primary)
                    .font(DSFont.row.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityValue(presentation.accessibilityValue)
                Text(subtitle(for: node, flowerName: presentation.secondary))
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .modifier(CappedWidth(cap: titleCap))
            .layoutPriority(1)
            .help(presentation.helpText)
        } else if let selectedProject {
            Text(selectedProject.name)
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .modifier(CappedWidth(cap: titleCap))
        }
    }

    /// タイトルは内容の幅。最大は幅の段階で 300 / 210 / 150（PhloxWindow.dc.html:707）。
    private var titleCap: CGFloat {
        switch density {
        case .full: 300
        case .compact: 210
        case .minimal: 150
        }
    }

    /// 「花名 · 短縮 ID · プロジェクト」。
    private func subtitle(for node: SessionNode, flowerName: String?) -> String {
        let projectName = node.projectID.flatMap { id in viewModel.projects.first { $0.id == id }?.name }
        // 短縮 ID は小文字 4 桁（「ツバキ · a3f9 · phlox-core」）。
        let shortID = String(node.id.rawValue.uuidString.prefix(4)).lowercased()
        return [flowerName, shortID, projectName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - worktree 隔離（プロジェクト選択時だけ）

    @ViewBuilder
    private var worktreeMenu: some View {
        if let selectedProject {
            WorktreeMenuButton(
                project: selectedProject,
                showsText: density == .full,
                isOn: worktreeIsolationBinding,
                onRename: { router.projectRenameRequest = selectedProject.id }
            )
        }
    }

    private var worktreeIsolationBinding: Binding<Bool> {
        Binding(
            get: { selectedProject?.usesWorktreeIsolation ?? false },
            set: { enabled in
                guard let projectID = router.selectedProjectID else { return }
                viewModel.setWorktreeIsolationEnabled(enabled, for: projectID)
            }
        )
    }

    // MARK: - 使用量・インスペクタ

    /// インスペクタの開閉に関係なく常に出す。押すとインスペクタの「使用量」を開く（07）。
    private var usageChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.showUsageInInspector()
            }
        } label: {
            // 面は無く 0.5pt の輪郭だけ。インスペクタで使用量を開いている間は選択の面（PhloxWindow.dc.html:712）。
            UsageTopBarView(monitor: usageMonitor, density: density)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    router.inspectorVisible && router.inspectorTab == .usage ? DSColor.fillSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.controlBorder, lineWidth: 0.5) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .accessibilityLabel(Text(usageAccessibilityLabel))
    }

    private var usageAccessibilityLabel: String {
        let chips = UsageDisplay.topBarChips(usages: usageMonitor.usages, showUnavailable: false, now: Date())
        let parts = chips.compactMap { chip -> String? in
            guard let used = chip.shownBuckets.map(\.usedPercent).max() else { return nil }
            let remaining = Int(round(100 - max(0, min(100, used))))
            return String(format: AppLocalizedString.string("%@ 残り%lld%%", locale: locale), chip.kind.displayName, remaining)
        }
        let joined = parts.joined(separator: AppLocalizedString.string("、", locale: locale))
        return String(format: AppLocalizedString.string("使用量: %@。クリックで詳細", locale: locale), joined)
    }

    private var inspectorToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.toggleInspector()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(router.inspectorVisible ? DSColor.textPrimary : DSColor.textSecondary)
                .frame(width: 28, height: 24)
                .background(
                    router.inspectorVisible ? DSColor.fillSelected : Color.clear,
                    in: RoundedRectangle(cornerRadius: DSRadius.row)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("インスペクタ（⌃⌘I）")
        .accessibilityLabel(Text("インスペクタ（⌃⌘I）"))
        .accessibilityAddTraits(router.inspectorVisible ? .isSelected : [])
    }
}

/// サイドバー開閉。サイドバーの上端と、隠しているときのツールバー左端で使う。
/// 隠しているときは対応待ちの件数を添える（01 D3）。
struct SidebarToggleButton: View {
    @Bindable var router: AppRouter
    var attentionCount: Int = 0

    private var isShowing: Bool {
        router.sidebarVisible && (!router.sidebarLacksRoom || router.sidebarPeeking)
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.toggleSidebar()
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if !isShowing, attentionCount > 0 {
                        CountBadge(count: attentionCount)
                            .offset(x: 6, y: -4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(isShowing ? Text("サイドバーを隠す（⌃⌘S）") : Text("サイドバーを表示（⌃⌘S）"))
        .accessibilityLabel(isShowing ? Text("サイドバーを隠す（⌃⌘S）") : Text("サイドバーを表示（⌃⌘S）"))
    }
}

/// 件数の丸。accentFill の面に白文字。
struct CountBadge: View {
    let count: Int

    var body: some View {
        // PhloxWindow.dc.html:149: 最小 18×16、角丸 8、白 11/700。
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

/// 単体/グリッドの 2 セグメント。淡いトラックの上で、選択セグメントだけを面で示す。
struct ViewModeToggle: View {
    @Binding var mode: ViewMode
    let showsText: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            segment(.single, symbol: "square", title: AppLocalizedString.string("単体", locale: locale), key: "⌃⌘1")
            segment(.grid, symbol: "square.grid.2x2", title: AppLocalizedString.string("グリッド", locale: locale), key: "⌃⌘2")
        }
        .padding(DSSpacing.xxs)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("表示モード"))
    }

    private func segment(_ value: ViewMode, symbol: String, title: String, key: String) -> some View {
        ModeSegmentButton(
            identifier: "view-mode-\(value.rawValue)",
            symbol: symbol,
            title: showsText ? title : nil,
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
                    .font(.system(size: 12, weight: .medium))
                if let title {
                    Text(title)
                        .font(DSFont.auxiliary.weight(.medium))
                }
            }
            .padding(.horizontal, title == nil ? 0 : 10)
            // 見た目は 12 Design System のセグメント高 22、押せる範囲は DSHitTarget の 24。
            .frame(minWidth: DSHitTarget.modeSegmentWidth, minHeight: 22)
            .background(
                isOn ? DSColor.controlBackground : (hovering ? DSColor.fillSubtle : Color.clear),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .shadow(color: isOn ? .black.opacity(0.2) : .clear, radius: 0.75, y: 0.5)
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

/// 内容の幅のまま、上限 `cap` を超えるときだけ切り詰める（`.frame(maxWidth:)` は上限まで広がってしまう）。
private struct CappedWidth: ViewModifier {
    let cap: CGFloat
    func body(content: Content) -> some View {
        CappedWidthLayout(cap: cap) { content }
    }
}

private struct CappedWidthLayout: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? cap, cap)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// タイトル直後の worktree ボタンとそのメニュー（01 E4）。見出し・チェック項目・説明・名前の変更。
private struct WorktreeMenuButton: View {
    let project: Project
    let showsText: Bool
    @Binding var isOn: Bool
    let onRename: () -> Void

    @State private var presented = false
    @State private var hovering = false
    @Environment(\.locale) private var locale

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .medium))
                if showsText {
                    Text("worktree 隔離")
                        .font(DSFont.auxiliary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(presented ? DSColor.fillSelected : (hovering ? DSColor.fillSubtle : .clear), in: RoundedRectangle(cornerRadius: DSRadius.row))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
        .help("選択中プロジェクトのセッション隔離")
        .accessibilityLabel(Text("Git worktree 隔離"))
        .accessibilityValue(Text(isOn ? "オン" : "オフ"))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: project.name)
                    .font(DSFont.meta.weight(.semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Button { isOn.toggle() } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(isOn ? 1 : 0)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("git worktree で隔離する")
                                .font(DSFont.row)
                                .foregroundStyle(DSColor.textPrimary)
                            Text("オンにすると、このプロジェクトで以降に起動するセッションを個別の worktree で動かします。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(DSColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                Divider().padding(.vertical, 4)
                Button {
                    presented = false
                    onRename()
                } label: {
                    Text("プロジェクト名を変更…")
                        .font(DSFont.row)
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.leading, 30)
                        .padding(.trailing, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
            }
            .frame(width: 300)
            .background(DSColor.popoverBackground)
            .environment(\.locale, locale)
        }
    }
}
