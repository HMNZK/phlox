import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// グリッド表示のときだけツールバーの下に出す表示範囲バー（01 C1）。
/// 並びは 範囲 → 表示するセッションの選択 →（右寄せ）範囲外の対応待ち → レイアウト。
struct GridModeBar: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    @Binding var sessionPickerPresented: Bool

    var body: some View {
        let summary = GridScopeSummary.make(
            projects: viewModel.projects,
            filterProjectID: viewModel.gridSessionFilterProjectID,
            visibleCount: visibleIDs.count,
            hasSessionSelection: viewModel.gridSessionSelection != nil
        )
        HStack(spacing: DSSpacing.s) {
            Text(summary.text)
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(summary.accessibilityText)
                .accessibilityLabel(summary.accessibilityText)
            ForEach(summary.clearActions, id: \.self) { action in
                Button(action.label) {
                    switch action {
                    case .projectFilter:
                        router.clearGridFilter()
                    case .sessionSelection:
                        viewModel.clearGridSessionSelection()
                    }
                }
                .font(DSFont.auxiliary)
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.accentInk)
                .lineLimit(1)
                .help(action.label)
            }
            sessionSelectionButton
            Spacer(minLength: DSSpacing.s)
            if outOfScopeAttentionCount > 0 {
                Text("表示範囲の外に対応待ち \(outOfScopeAttentionCount) 件")
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
            }
            PaneLayoutPresetMenu { preset in
                viewModel.handlePaneLayoutAction(.applyPreset(preset))
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .frame(height: DSLayout.tabBarHeight)
        .background(DSColor.tabBarBackground)
    }

    private var visibleIDs: Set<SessionID> {
        Set(viewModel.filteredGridSessionNodes(projectID: viewModel.gridSessionFilterProjectID).map(\.id))
    }

    private var outOfScopeAttentionCount: Int {
        let visible = visibleIDs
        return viewModel.attentionEntries.filter { !visible.contains($0.id) }.count
    }

    private var sessionSelectionButton: some View {
        let candidates = viewModel.gridSessionPickerCandidates()
        let badge: String? = viewModel.gridSessionSelection.map { "\($0.count)/\(candidates.count)" }

        return Button {
            sessionPickerPresented.toggle()
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
            .frame(height: 24)
            .padding(.horizontal, badge == nil ? 0 : DSSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help("表示セッションを選択")
        .accessibilityLabel(Text(badge.map { String(localized: "表示するセッションを選択 \($0)") } ?? String(localized: "表示するセッションを選択")))
        .popover(isPresented: $sessionPickerPresented, arrowEdge: .bottom) {
            GridSessionPicker(
                candidates: candidates,
                isSelected: { viewModel.isGridSessionSelected($0) },
                onToggle: { viewModel.toggleGridSessionSelection($0) },
                onShowAll: { viewModel.clearGridSessionSelection() }
            )
        }
    }
}
