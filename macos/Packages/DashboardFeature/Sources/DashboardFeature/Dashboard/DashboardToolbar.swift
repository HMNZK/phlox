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
    @Environment(\.locale) private var locale

    /// 信号（閉じる・しまう・拡大）が占める幅。
    private static let trafficLightsWidth: CGFloat = 70

    var body: some View {
        HStack(spacing: DSSpacing.m) {
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
            if showUsageInHeader {
                usageChip
            }
            Rectangle()
                .fill(DSColor.separator)
                .frame(width: 1, height: 20)
            inspectorToggleButton
        }
        .padding(.horizontal, DSSpacing.m)
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
            .frame(maxWidth: 320, alignment: .leading)
            .layoutPriority(1)
            .help(presentation.helpText)
        } else if let selectedProject {
            Text(selectedProject.name)
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    /// 「花名 · 短縮 ID · プロジェクト」。
    private func subtitle(for node: SessionNode, flowerName: String?) -> String {
        let projectName = node.projectID.flatMap { id in viewModel.projects.first { $0.id == id }?.name }
        return [flowerName, SessionViewModel.shortID(for: node.id), projectName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - worktree 隔離（プロジェクト選択時だけ）

    @ViewBuilder
    private var worktreeMenu: some View {
        if let selectedProject {
            let isOn = selectedProject.usesWorktreeIsolation
            Menu {
                Toggle(isOn: worktreeIsolationBinding) {
                    Label("セッションを Git worktree で隔離", systemImage: "arrow.triangle.branch")
                }
            } label: {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: DSIconSize.m, weight: .medium))
                    if density == .full {
                        Text("worktree 隔離")
                            .font(DSFont.auxiliary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DSColor.textSecondary)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.xs)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .buttonStyle(HoverableIconButtonStyle())
            .help("選択中プロジェクトのセッション隔離")
            .accessibilityLabel(Text("Git worktree 隔離"))
            .accessibilityValue(Text(isOn ? "オン" : "オフ"))
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

    /// インスペクタの開閉に関係なく常に出す。押すとインスペクタを開く（「使用量」タブは 07 の段で分ける）。
    private var usageChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.inspectorVisible = true
            }
        } label: {
            UsageTopBarView(monitor: usageMonitor, density: density)
                .padding(.horizontal, DSSpacing.s)
                .frame(height: 28)
                .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.row))
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
            return String(localized: "\(chip.kind.displayName) 残り\(remaining)%")
        }
        return String(localized: "使用量: \(parts.joined(separator: String(localized: "、")))。クリックで詳細")
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
                .frame(width: 28, height: 28)
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
        Text("\(count)")
            .font(.system(size: 10.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(DSColor.accentFill, in: Capsule())
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
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s + 3))
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
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                if let title {
                    Text(title)
                        .font(DSFont.auxiliary)
                }
            }
            .padding(.horizontal, title == nil ? 0 : DSSpacing.s)
            .frame(minWidth: DSHitTarget.modeSegmentWidth, minHeight: DSHitTarget.modeSegmentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? DSColor.textPrimary : DSColor.textSecondary)
        .background(
            isOn ? DSColor.cardBackground : (hovering ? DSColor.fillSubtle : Color.clear),
            in: RoundedRectangle(cornerRadius: DSRadius.s)
        )
        .shadow(color: isOn ? .black.opacity(0.08) : .clear, radius: 1, y: 0.5)
        .onHover { hovering = $0 }
        .pointingHandCursor()
        .help(help)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
