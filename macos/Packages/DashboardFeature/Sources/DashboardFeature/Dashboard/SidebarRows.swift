import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

// 03 Sidebar の行。寸法はモック（PhloxSidebar）の値: プロジェクト行 28pt・セッション行 26pt・
// 1 段 16pt の字下げ（先頭 22pt）・行の角丸 6。

/// 1 段目の行頭の余白と、1 段ごとの字下げ。
enum SidebarRowMetrics {
    static let firstIndent: CGFloat = 22
    static let indentStep: CGFloat = 16

    static func leadingPadding(depth: Int) -> CGFloat {
        firstIndent + CGFloat(max(depth - 1, 0)) * indentStep
    }
}

// MARK: - Project row

struct SidebarProjectRow<Menu: View, NewSession: View>: View {
    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let isScoped: Bool
    let showsScopeMark: Bool
    let collapsedSummary: SidebarCollapsedSummary
    let running: RunningSessionBreakdown
    let sessionCount: Int
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onSelect: (_ commandPressed: Bool) -> Void
    let onToggleExpansion: () -> Void
    /// 引数は ↩ で確定したか（ほかへ移って確定したときは入力先を動かさない）。
    let onCommitRename: (_ byReturn: Bool) -> Void
    let onCancelRename: () -> Void
    @ViewBuilder let menu: () -> Menu
    @ViewBuilder let newSessionMenu: () -> NewSession

    @State private var isHovering = false
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var emphasis: SidebarRowEmphasis {
        .resolve(.projectScope(isFiltering: isScoped, isDefaultTarget: isSelected, isHovering: isHovering))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? Text("折りたたむ") : Text("展開"))
            .accessibilityLabel(isExpanded ? Text("折りたたむ") : Text("展開"))
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            if isRenaming {
                SidebarRenameField(
                    text: $renameDraft,
                    hint: "↩ 確定 · Esc 取消 · 変わるのは表示名だけです（フォルダ名は変わりません）",
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
            } else {
                Text(verbatim: project.name)
                    .font(DSFont.row.weight(emphasis.nameWeight))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isHovering, !isRenaming {
                SwiftUI.Menu(content: newSessionMenu) {
                    SidebarRowIcon(text: "＋", isPrimary: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("このプロジェクトに新規セッション"))
                .accessibilityLabel(Text("このプロジェクトに新規セッション"))
                SwiftUI.Menu(content: menu) {
                    SidebarRowIcon(text: "⋯", isPrimary: false)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("プロジェクトの操作"))
                .accessibilityLabel(Text("プロジェクトの操作"))
            } else if !isRenaming {
                trailingMeta
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(emphasis.fill, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(NSEvent.modifierFlags.contains(.command))
        }
        .onHover { isHovering = $0 }
        .contextMenu(menuItems: menu)
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(emphasis.accessibilityValue.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { onSelect(false) }
        .accessibilityAction(named: isExpanded ? Text("折りたたむ") : Text("展開"), onToggleExpansion)
    }

    /// 右端: 畳んだ行の要約・「n 実行中」（無ければ畳んだ行の件数）・グリッドの表示範囲の印。
    @ViewBuilder
    private var trailingMeta: some View {
        let trailing = SidebarRowMeta.project(isExpanded: isExpanded, summary: collapsedSummary, runningCount: running.total)
        if trailing.showsSummary {
            SidebarSummaryText(summary: collapsedSummary)
        }
        if trailing.showsRunning {
            RunningCountBadge(count: running.total, nestedOrchestrationCount: running.nestedOrchestration)
        } else if trailing.showsCount {
            Text(verbatim: "\(sessionCount)")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .monospacedDigit()
        }
        if showsScopeMark {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DSColor.accentInk)
                .help(Text("グリッドの表示範囲"))
                .accessibilityLabel(Text("グリッドの表示範囲"))
        }
    }

    private var accessibilityText: Text {
        let state = isExpanded ? Text("展開") : Text("折りたたみ")
        let path = (project.directoryPath as NSString).abbreviatingWithTildeInPath
        return isSelected
            ? Text("プロジェクト \(project.name)、\(path)、\(state)、選択中")
            : Text("プロジェクト \(project.name)、\(path)、\(state)")
    }
}

// MARK: - Session row

struct SidebarSessionRow<Menu: View>: View {
    let node: SessionNode
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let childCount: Int
    let descendantSummary: SidebarCollapsedSummary
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onSelect: () -> Void
    let onToggleExpansion: () -> Void
    let onCommitRename: (_ byReturn: Bool) -> Void
    let onCancelRename: () -> Void
    @ViewBuilder let menu: () -> Menu

    @State private var isHovering = false
    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var state: SessionDisplayState { node.tabDisplayState }
    private var isUnread: Bool { state == .doneUnread }
    private var padding: CGFloat { SidebarRowMetrics.leadingPadding(depth: depth) }

    private var emphasis: SidebarRowEmphasis {
        .resolve(.session(isCurrent: isSelected, isHovering: isHovering, hasUnseenCompletion: isUnread))
    }

    var body: some View {
        HStack(spacing: 7) {
            if isRenaming {
                SidebarRenameField(
                    text: $renameDraft,
                    hint: "↩ 確定 · Esc 取消 · 空欄で自動の名前に戻す",
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
            } else {
                Text(verbatim: node.displayName)
                    .font(DSFont.row.weight(emphasis.nameWeight))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isUnread {
                    Circle()
                        .fill(DSColor.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                if hasChildren, !isExpanded {
                    HStack(spacing: 3) {
                        Text(verbatim: "+\(childCount)")
                        SidebarSummaryText(summary: descendantSummary)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(DSColor.fillSelected, in: Capsule())
                }
                if isHovering {
                    SwiftUI.Menu(content: menu) {
                        SidebarRowIcon(text: "⋯", isPrimary: false)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text("セッションの操作"))
                    .accessibilityLabel(Text("セッションの操作"))
                } else {
                    Text(verbatim: node.agentDescriptor.tabInitials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.textTertiary)
                        .frame(minWidth: 13)
                    meta
                }
            }
        }
        .padding(.leading, padding)
        .padding(.trailing, 8)
        .frame(minHeight: 26)
        .background(alignment: .leading) { guides }
        .overlay(alignment: .leading) { chevron }
        .background(emphasis.fill, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .contextMenu(menuItems: menu)
        .help(Text(verbatim: helpText))
        // 名前の編集中は入力欄に届くよう子を残す。
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(emphasis.accessibilityValue.map { Text(LocalizedStringKey($0)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityActions {
            if hasChildren {
                Button(isExpanded ? "折りたたむ" : "展開", action: onToggleExpansion)
            }
        }
    }

    /// 右端: 待機は経過時間（1 分ごと）、それ以外は状態の文言（対応待ちは状態色）。
    @ViewBuilder
    private var meta: some View {
        if SidebarRowMeta.session(state) == .elapsed {
            TimelineView(.periodic(from: node.startedAt, by: 60)) { context in
                Text(verbatim: SidebarRelativeTime.label(from: node.startedAt, to: context.date, locale: locale))
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        } else {
            Text(verbatim: state.localizedLabel(locale: locale))
                .font(DSFont.meta.weight(state.attentionKind != nil ? .semibold : state == .running ? .medium : .regular))
                .foregroundStyle(state.color)
                .fixedSize()
        }
    }

    /// 縦の案内線（親の段ごと）。
    private var guides: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(1..<max(depth, 1)), id: \.self) { level in
                Rectangle()
                    .fill(DSColor.separator)
                    .frame(width: 1)
                    .offset(x: SidebarRowMetrics.leadingPadding(depth: level) + 5)
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    /// 子を持つ行の左余白のシェブロン。
    @ViewBuilder
    private var chevron: some View {
        if hasChildren {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: padding - 13)
            .help(isExpanded ? Text("折りたたむ") : Text("展開"))
        }
    }

    private var helpText: String {
        SessionTitlePresentation(
            state: node.titleState,
            fallback: SessionViewModel.shortID(for: node.id),
            workspacePath: node.workspacePath
        ).helpText
    }

    /// 「タイトル、状態、未読、エージェント、子セッション n 件」（モックの aria-label と同じ並び）。
    /// 語は画面の言語設定で引くため Text でつなぐ。
    private var accessibilityText: Text {
        var parts = [Text(verbatim: node.displayName), Text(verbatim: state.localizedLabel(locale: locale))]
        if isUnread { parts.append(Text("未読")) }
        parts.append(Text(verbatim: node.agentDescriptor.displayName))
        if hasChildren { parts.append(Text("子セッション \(childCount) 件")) }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text("、") + $1 }
    }
}

// MARK: - Parts

/// 畳んだ行の要約。対応待ちは「承認待ち 1」のように状態色の文字、未読の完了は「未読 1」。
struct SidebarSummaryText: View {
    let summary: SidebarCollapsedSummary
    @Environment(\.locale) private var locale

    var body: some View {
        if !summary.isEmpty {
            HStack(spacing: 5) {
                ForEach(summary.attention, id: \.kind) { entry in
                    Text(verbatim: "\(Self.state(for: entry.kind).localizedLabel(locale: locale)) \(entry.count)")
                        .foregroundStyle(DSColor.attentionInk(entry.kind))
                }
                if summary.unread > 0 {
                    Text("未読 \(summary.unread)")
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .font(DSFont.meta.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
        }
    }

    static func state(for kind: AttentionKind) -> SessionDisplayState {
        switch kind {
        case .approval: .approval
        case .question: .question
        case .error: .error
        case .stalled: .stalled
        }
    }
}

/// 行の右端でホバー中だけ出す ＋ / ⋯。
struct SidebarRowIcon: View {
    let text: String
    let isPrimary: Bool

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .foregroundStyle(isPrimary ? DSColor.textPrimary : DSColor.textSecondary)
            .frame(width: 20, height: 18)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
    }
}

/// 行の中での名前変更（03 F6）。↩ で確定、Esc で取り消し、ほかへ移ると確定。
struct SidebarRenameField: View {
    @Binding var text: String
    let hint: LocalizedStringKey
    let onCommit: (_ byReturn: Bool) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            // 案内は行の中に出す（重ね表示だと下の行の文字と重なる）。
            Text(hint)
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }

    private var field: some View {
        TextField(text: $text) { Text("名前") }
            .textFieldStyle(.plain)
            .font(DSFont.row)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.accent, lineWidth: 2))
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { onCommit(true) }
            .onExitCommand(perform: onCancel)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { onCommit(false) }
            }
            .help(Text(hint))
    }
}
