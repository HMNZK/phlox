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
            outOfScopeButton
            PaneLayoutPresetMenu(
                currentName: AppLocalizedString.string(viewModel.paneLayoutPresetState.preset.displayName, locale: locale),
                isAdjusted: viewModel.paneLayoutPresetState.isAdjusted
            ) { preset in
                viewModel.handlePaneLayoutAction(.applyPreset(preset))
            }
        }
        .font(.system(size: 12))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(DSColor.tabBarBackground)
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

    /// 範囲外の対応待ちを状態ごとの件数で出す（S6「エラー 1 無応答 1 が範囲外」）。押すと対応待ちの一覧。
    @ViewBuilder
    private var outOfScopeButton: some View {
        let counts = outOfScopeCounts
        if !counts.isEmpty {
            Button { router.attentionListPresented = true } label: {
                HStack(spacing: 6) {
                    ForEach(counts, id: \.kind) { entry in
                        Text(verbatim: "\(GridOutOfScopeAttention.state(entry.kind).localizedLabel(locale: locale)) \(entry.count)")
                            .fontWeight(.semibold)
                            .foregroundStyle(DSColor.attentionInk(entry.kind))
                    }
                    Text("が範囲外")
                        .foregroundStyle(DSColor.textPrimary)
                    Text(verbatim: "›")
                        .foregroundStyle(DSColor.textTertiary)
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("対応待ちの一覧（⌥⌘J）"))
        }
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

    /// 範囲外の対応待ち（承認・質問・エラー・無応答の順）。
    private var outOfScopeCounts: [(kind: AttentionKind, count: Int)] {
        let visible = visibleIDs
        return GridOutOfScopeAttention.counts(viewModel.attentionEntries.filter { !visible.contains($0.id) })
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

/// 範囲外の対応待ちの数え方（表示範囲バー）。
enum GridOutOfScopeAttention {
    static func state(_ kind: AttentionKind) -> SessionDisplayState {
        switch kind {
        case .approval: .approval
        case .question: .question
        case .error: .error
        case .stalled: .stalled
        }
    }

    static func counts(_ entries: [AttentionEntry]) -> [(kind: AttentionKind, count: Int)] {
        AttentionKind.allCases.compactMap { kind in
            let count = entries.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
    }
}
