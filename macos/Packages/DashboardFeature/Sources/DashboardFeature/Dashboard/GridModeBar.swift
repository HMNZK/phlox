import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// グリッド表示のときだけツールバーの下に出す表示範囲バー（01 C1）。
/// 並びは 範囲 → 表示するセッションの選択 → レイアウト。
struct GridModeBar: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let gridViewport: GridViewport
    @Binding var sessionPickerPresented: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        let summary = GridScopeSummary.make(
            projects: viewModel.projects,
            filterProjectID: viewModel.gridSessionFilterProjectID,
            visibleCount: visibleIDs.count,
            hasSessionSelection: viewModel.gridSessionSelection != nil
        )
        HStack(spacing: DSSpacing.s) {
            Text("表示範囲")
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            scopeToken(summary)
            sessionSelectionButton
            Spacer(minLength: DSSpacing.s)
            PaneLayoutPresetMenu(
                currentName: AppLocalizedString.string(viewModel.gridLayoutState.isAutomatic ? "自動" : viewModel.paneLayoutPresetState.preset.displayName, locale: locale),
                isAdjusted: !viewModel.gridLayoutState.isAutomatic && viewModel.paneLayoutPresetState.isAdjusted,
                canUndoAutomatic: viewModel.canUndoAutomaticGridLayout,
                onAutomatic: { viewModel.restoreAutomaticGridLayout() },
                onUndoAutomatic: { viewModel.undoAutomaticGridLayout() }
            ) { preset in
                viewModel.handlePaneLayoutAction(.applyPreset(preset), in: gridViewport.size)
            }
        }
        .font(DSFont.auxiliary)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(DSColor.background)
    }

    /// 1 軸目: プロジェクト。絞り込み中は ✕ で「すべて」に戻す（S6）。
    private func scopeToken(_ summary: GridScopeSummary) -> some View {
        let filtered = summary.clearActions.contains(.projectFilter)
        let title = filtered ? summary.title : AppLocalizedString.string(summary.title, locale: locale)
        return HStack(spacing: 6) {
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
            if filtered {
                clearButton(label: "プロジェクトの絞り込みを解除") { router.clearGridFilter() }
            }
        }
        .modifier(GridScopeTokenStyle(isActive: filtered))
        // 長いプロジェクト名は切れるので、ヘルプで全体を出す。
        .help(Text(verbatim: title))
    }

    private func clearButton(label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    private var visibleIDs: Set<SessionID> {
        Set(viewModel.filteredGridSessionNodes(projectID: viewModel.gridSessionFilterProjectID).map(\.id))
    }

    /// 2 軸目: 表示するセッションの選択（S6「3 / 4 件を表示」）。選択中は ✕ で解除する。
    private var sessionSelectionButton: some View {
        let candidates = viewModel.gridSessionPickerCandidates()
        let visible = visibleIDs.count
        let picked = viewModel.gridSessionSelection != nil
        let filtered = viewModel.gridSessionFilterProjectID != nil

        return HStack(spacing: 6) {
            Button {
                sessionPickerPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    if picked {
                        Text("\(visible) / \(candidates.count) 件を表示")
                    } else if filtered {
                        Text("\(visible) / \(candidates.count) 件（すべて）")
                    } else {
                        Text("\(visible) 件")
                    }
                    Text(verbatim: "▾").font(.system(size: 9)).opacity(0.7)
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DSColor.textPrimary)
            .help(Text("表示するセッションを選択"))
            .accessibilityLabel(Text("表示するセッションを選択"))
            .accessibilityHint(picked ? Text("\(visible) / \(candidates.count) 件を表示") : Text("\(visible) 件"))
            if picked {
                clearButton(label: "セッション選択を解除") { viewModel.clearGridSessionSelection() }
            }
        }
        .modifier(GridScopeTokenStyle(isActive: picked))
        .popover(isPresented: $sessionPickerPresented, arrowEdge: .bottom) {
            GridSessionPicker(
                candidates: candidates,
                isSelected: { viewModel.isGridSessionSelected($0) },
                onToggle: { viewModel.toggleGridSessionSelection($0) },
                onShowAll: { viewModel.clearGridSessionSelection() }
            )
            .environment(\.locale, locale)
        }
    }
}

/// 表示範囲バーのトークン（S6）。絞り込み中は面、そうでなければ細い縁。
private struct GridScopeTokenStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, 9)
            .padding(.trailing, isActive ? 3 : 9)
            .frame(height: 22)
            .background(isActive ? DSColor.fillSelected : Color.clear, in: Capsule())
            .overlay {
                if !isActive { Capsule().strokeBorder(DSColor.separator, lineWidth: 1) }
            }
    }
}
