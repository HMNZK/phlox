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
/// 中央と右インスペクタの上に渡る 38pt のツールバー。単体とグリッドで並びを変えない。
/// 左: （サイドバーを隠しているとき）信号の右にサイドバー開閉。右: 表示モード・対応待ち・使用量・インスペクタ。
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
            Spacer(minLength: DSSpacing.s)
            ViewModeToggle(mode: $router.viewMode, showsText: density != .minimal)
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
                .frame(width: 28, height: 24)
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

/// 件数の丸。accentFill の面に白文字。
struct CountBadge: View {
    let count: Int

    var body: some View {
        // PhloxWindow.dc.html:149: 最小 18×16、角丸 8、白 11/700。
        Text("\(count)")
            .font(DSFont.meta.weight(.bold))
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
                    .font(DSFont.auxiliary.weight(.medium))
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
