import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

struct DashboardLeadingTopBarControls: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            sidebarToggleButton
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("設定")
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.toggleSidebar()
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(router.sidebarVisible ? "サイドバーを隠す" : "サイドバーを表示")
    }
}

struct DashboardTrailingTopBarControls: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Bindable var usageMonitor: UsageMonitor
    let windowWidth: CGFloat
    let occupiedSidebarWidth: CGFloat
    @Binding var gridColumnsRaw: String
    @Binding var gridSessionPickerPresented: Bool

    @State private var measuredControlsWidth: CGFloat = 0
    @State private var hasMeasuredControlsWidth = false
    @State private var trailingControlsGeometryWidth: CGFloat = 0

    private var usageAvailableWidth: CGFloat {
        TrailingTopBarLayout.usageAvailableWidth(
            windowWidth: windowWidth,
            occupiedSidebarWidth: occupiedSidebarWidth,
            measuredControlsWidth: effectiveControlsWidth,
            spacing: DSSpacing.s,
            trailingPadding: DSSpacing.m
        )
    }

    private var effectiveControlsWidth: CGFloat {
        TrailingTopBarLayout.effectiveControlsWidth(
            measured: measuredControlsWidth,
            hasMeasured: hasMeasuredControlsWidth,
            viewMode: router.viewMode
        )
    }

    var body: some View {
        HStack(spacing: DSSpacing.s) {
            // UsageLimit ビュー(インスペクター)表示中は詳細が見えているため
            // トップバーのチップは出さない。
            if !router.inspectorVisible {
                UsageTopBarView(
                    monitor: usageMonitor,
                    availableWidth: usageAvailableWidth
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            trailingControls
        }
        // 高さ32の中央寄せで、操作系の中心を三色ボタン・左トグルと同じ y=16 に揃える。
        .frame(height: 32)
    }

    private var trailingControls: some View {
        HStack(spacing: DSSpacing.s) {
            modeToggle
            if router.viewMode == .grid {
                gridSessionSelectionButton
                gridColumnsToggle
            }
            inspectorToggleButton
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        trailingControlsGeometryWidth = geometry.size.width
                        updateMeasuredControlsWidth(geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        trailingControlsGeometryWidth = newWidth
                        updateMeasuredControlsWidth(newWidth)
                    }
            }
        }
        .onChange(of: router.viewMode) { _, _ in
            hasMeasuredControlsWidth = false
            // single→team などコントロール幅が不変でも見積りへ戻した直後に
            // 直前の実測値で再確定する（geometry onChange が発火しないケース対策）。
            updateMeasuredControlsWidth(trailingControlsGeometryWidth)
        }
    }

    private func updateMeasuredControlsWidth(_ newWidth: CGFloat) {
        let updated = TrailingTopBarLayout.applyWidthMeasurement(
            newWidth: newWidth,
            currentMeasured: measuredControlsWidth,
            hasMeasured: hasMeasuredControlsWidth
        )
        measuredControlsWidth = updated.measured
        hasMeasuredControlsWidth = updated.hasMeasured
    }

    private var modeToggle: some View {
        // 標準セグメントの明るいベゼルを避け、淡いトラックの上で選択セグメントだけを
        // fill で示すボーダーレストグル。選択/ホバーを「枠」ではなく「面」で表現する。
        ViewModeToggle(mode: $router.viewMode)
            .help("表示モードを切り替え")
    }

    private var gridColumns: GridColumns {
        GridColumns(rawValue: gridColumnsRaw) ?? .auto
    }

    private var gridColumnsBinding: Binding<GridColumns> {
        Binding(
            get: { gridColumns },
            set: { gridColumnsRaw = $0.rawValue }
        )
    }

    private var gridColumnsToggle: some View {
        GridColumnsToggle(columns: gridColumnsBinding)
            .help("グリッドの列数を選択")
    }

    private var gridSessionPickerCandidates: [SessionNode] {
        viewModel.gridSessionPickerCandidates()
    }

    private var gridSessionSelectionButton: some View {
        let candidates = gridSessionPickerCandidates
        let badge: String? = {
            guard let selection = viewModel.gridSessionSelection else { return nil }
            return "\(selection.count)/\(candidates.count)"
        }()

        return Button {
            gridSessionPickerPresented.toggle()
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: DSIconSize.l, weight: .medium))
                if let badge {
                    Text(badge)
                        .font(DSFont.captionStrong)
                }
            }
            .foregroundStyle(DSColor.textSecondary)
            .frame(height: 28)
            .padding(.horizontal, badge == nil ? 0 : DSSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("表示セッションを選択")
        .popover(isPresented: $gridSessionPickerPresented, arrowEdge: .top) {
            GridSessionPicker(
                candidates: candidates,
                isSelected: { viewModel.isGridSessionSelected($0) },
                onToggle: { viewModel.toggleGridSessionSelection($0) },
                onShowAll: { viewModel.clearGridSessionSelection() }
            )
        }
    }

    private var inspectorToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                router.toggleInspector()
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: DSIconSize.l, weight: .medium))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(router.inspectorVisible ? "インスペクターを隠す" : "インスペクターを表示")
    }
}

/// グリッド列数（Auto/1/2/3/4）のボーダーレストグル。
private struct GridColumnsToggle: View {
    @Binding var columns: GridColumns

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(GridColumns.allCases, id: \.self) { value in
                GridColumnSegmentButton(
                    label: value.selectorLabel,
                    help: columnHelp(value),
                    isOn: columns == value,
                    action: { columns = value }
                )
            }
        }
        .padding(DSSpacing.xxs)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s + 3))
    }

    private func columnHelp(_ value: GridColumns) -> String {
        switch value {
        case .auto:
            return String(localized: "列数を自動（⌈√N⌉）")
        case .one:
            return String(localized: "1列表示")
        case .two:
            return String(localized: "2列表示")
        case .three:
            return String(localized: "3列表示")
        case .four:
            return String(localized: "4列表示")
        }
    }
}

private struct GridColumnSegmentButton: View {
    let label: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DSFont.captionStrong)
                .frame(minWidth: 22, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? DSColor.textPrimary : DSColor.textSecondary)
        .background(
            isOn ? DSColor.fillSelected : (hovering ? DSColor.fillSubtle : Color.clear),
            in: RoundedRectangle(cornerRadius: DSRadius.s)
        )
        .onHover { isHovering in
            hovering = isHovering
        }
        .pointingHandCursor()
        .help(help)
    }
}

/// 単体/グリッド表示のボーダーレストグル。淡いトラックの上で、選択セグメントのみ
/// fill で示す。標準セグメントコントロールの明るいベゼルを避けるためのカスタム実装。
private struct ViewModeToggle: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            segment(.single, symbol: "square", help: String(localized: "単体表示"))
            segment(.grid, symbol: "square.grid.2x2", help: String(localized: "グリッド表示"))
            segment(.team, symbol: "person.3", help: TeamViewBranding.displayTitle)
        }
        .padding(DSSpacing.xxs)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.s + 3))
    }

    private func segment(_ value: ViewMode, symbol: String, help: String) -> some View {
        ModeSegmentButton(
            symbol: symbol,
            help: help,
            isOn: mode == value,
            action: { mode = value }
        )
    }
}

private struct ModeSegmentButton: View {
    let symbol: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 選択は fillSelected、未選択ホバーは fillSubtle で「面」として状態を示す。
        .foregroundStyle(isOn ? DSColor.textPrimary : DSColor.textSecondary)
        .background(
            isOn ? DSColor.fillSelected : (hovering ? DSColor.fillSubtle : Color.clear),
            in: RoundedRectangle(cornerRadius: DSRadius.s)
        )
        .onHover { isHovering in
            hovering = isHovering
        }
        .pointingHandCursor()
        .help(help)
    }
}
