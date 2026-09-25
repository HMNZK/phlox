import SwiftUI
import UniformTypeIdentifiers
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
    /// ＋ で開く新規セッションの表（Sidebar F5）。
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
                // PhloxSidebar.dc.html: 文字「›」13pt・幅 10、開くと 90°。
                Text(verbatim: "›")
                    .font(DSFont.row)
                    .foregroundStyle(DSColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? Text("折りたたむ") : Text("展開"))
            .accessibilityLabel(isExpanded ? Text("折りたたむ") : Text("展開"))
            FolderShape()
                .stroke(DSColor.textSecondary, lineWidth: 1.2)
                .frame(width: 16, height: 13)
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
                NewSessionPopoverButton(table: newSessionMenu) {
                    SidebarRowIcon(text: "＋", isPrimary: true)
                }
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
        .modifier(SidebarMenuOpenRing(menu: menu))
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
            GridScopeShape()
                .stroke(DSColor.accentInk, lineWidth: 1.4)
                .frame(width: 12, height: 11)
                .help(Text("グリッドの表示範囲"))
                .accessibilityLabel(Text("グリッドの表示範囲"))
        }
    }

    private var accessibilityText: Text {
        let state = isExpanded ? Text("展開中") : Text("折りたたみ")
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
    /// 読み上げの経過を 1 分ごとに作り直すための時計。
    @State private var labelClock = Date()
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
                    hint: "↩ 確定 · Esc 取消 · 空欄で「\(SessionViewModel.shortID(for: node.id))」に戻す",
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
                    // 「+2 ▲」: 件数と、子の中の対応待ち・未読を記号だけで（PhloxSidebar.dc.html:133）。
                    HStack(spacing: 3) {
                        Text(verbatim: "+\(childCount)")
                        SidebarSummaryText(summary: descendantSummary, showsCounts: false)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 8))
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
        .background(alignment: .leading) { SidebarGuides(depth: depth) }
        .overlay(alignment: .leading) { chevron }
        .background(emphasis.fill, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .modifier(SidebarMenuOpenRing(menu: menu))
        .help(Text(verbatim: helpText))
        // 名前の編集中は入力欄に届くよう子を残す。
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: elapsedSince) {
            guard elapsedSince != nil else { return }
            while !Task.isCancelled {
                // 経過の起点から数えて次の 1 分の境目まで待つ（表示した時刻に引きずられない）。
                let offset = elapsedSince.map { Date().timeIntervalSince($0) } ?? 0
                try? await Task.sleep(for: .seconds(60 - offset.truncatingRemainder(dividingBy: 60) + 0.05))
                labelClock = Date()
            }
        }
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
        } else if state == .stalled {
            // 「無応答 2:14」（13 Review）。1 秒ごとに更新する。
            TimelineView(.periodic(from: .now, by: 1)) { context in
                stateText(node.stalledSilence(now: context.date).map {
                    "\(state.localizedLabel(locale: locale)) \(StallClock.text($0))"
                } ?? state.localizedLabel(locale: locale))
            }
        } else {
            stateText(state.localizedLabel(locale: locale))
        }
    }

    private func stateText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DSFont.meta.weight(state.attentionKind != nil ? .semibold : state == .running ? .medium : .regular))
            .monospacedDigit()
            .foregroundStyle(state.color)
            .fixedSize()
    }

    /// 子を持つ行の左余白のシェブロン。
    @ViewBuilder
    private var chevron: some View {
        if hasChildren {
            Button(action: onToggleExpansion) {
                // PhloxSidebar.dc.html: 文字「›」13pt・幅 10、開くと 90°。
                Text(verbatim: "›")
                    .font(DSFont.row)
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

    /// 読み上げの経過の起点（対応待ちは状態に入った時刻、待機は行の右端と同じ時刻）。
    private var elapsedSince: Date? {
        state.attentionKind != nil ? node.statusEnteredAt
            : SidebarRowMeta.session(state) == .elapsed ? node.startedAt : nil
    }

    /// 「タイトル、状態、経過、未読、エージェント、子セッション n 件」（モックの aria-label と同じ並び）。
    /// 経過は「待機、42分前」「承認待ち、3分前から」（1 分未満は付けない）。語は画面の言語設定で引くため Text でつなぐ。
    private var accessibilityText: Text {
        var parts = [Text(verbatim: node.displayName), Text(verbatim: state.localizedLabel(locale: locale))]
        let since = elapsedSince
        // labelClock を読むことで、1 分ごとに読み上げの経過を作り直す。
        let now = max(labelClock, Date())
        if let since, now.timeIntervalSince(since) >= 60 {
            let elapsed = SidebarRelativeTime.label(from: since, to: now, locale: locale)
            parts.append(state.attentionKind != nil ? Text("\(elapsed)前から") : Text("\(elapsed)前"))
        }
        if isUnread { parts.append(Text("未読")) }
        parts.append(Text(verbatim: node.agentDescriptor.displayName))
        if hasChildren { parts.append(Text("子セッション \(childCount) 件")) }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text("、") + $1 }
    }
}

// MARK: - Internal sessions row

/// オーケストレーションの内部セッションを親ごとにまとめた行（PhloxSidebar の isInternal。高さ 24・破線の四角）。
struct SidebarInternalSessionsRow: View {
    let depth: Int
    let count: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    private var padding: CGFloat { SidebarRowMetrics.leadingPadding(depth: depth) }

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(DSColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text("内部セッション（オーケストレーション）")
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "\(count)")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .monospacedDigit()
        }
        .padding(.leading, padding)
        .padding(.trailing, 8)
        .frame(height: 24)
        .background(alignment: .leading) { SidebarGuides(depth: depth) }
        .overlay(alignment: .leading) {
            Text(verbatim: "›")
                .font(DSFont.row)
                .foregroundStyle(DSColor.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10, height: 20)
                .offset(x: padding - 13)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .help(isExpanded ? Text("折りたたむ") : Text("展開"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("内部セッション \(count) 件、\(isExpanded ? Text("展開中") : Text("折りたたみ"))"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onToggle)
    }
}

// MARK: - Reorder

/// 並べ替えの挿入位置の線（PhloxSidebar の drag: 左 18・右 6・2pt の accent、左端に 6pt の丸）。
struct SidebarInsertionLine: View {
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(DSColor.accent)
                .frame(height: 2)
                .padding(.leading, 18)
                .padding(.trailing, 6)
            Circle()
                .fill(DSColor.sidebarBackground)
                .overlay(Circle().strokeBorder(DSColor.accent, lineWidth: 2))
                .frame(width: 6, height: 6)
                .padding(.leading, 14)
        }
        .frame(height: 6)
        .offset(y: -2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 並べ替えで運ぶ中身の型。アプリの外にも宣言にも出ない型なので、外から持ち込んだ文字などは受け付けない。
enum SidebarReorderPayload {
    static let type = UTType(tag: "phlox-sidebar-session", tagClass: .filenameExtension, conformingTo: .data)!

    static func provider(for id: SessionID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(id.rawValue.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

/// 行へのドロップ。上半分なら行の前、下半分なら後ろへ入れる。兄弟でない行には落とせない。
struct SidebarReorderDropDelegate: DropDelegate {
    let target: SessionID
    @Binding var dragging: SessionID?
    let siblings: () -> [SessionID]
    @Binding var dropTarget: SidebarDropTarget?
    let onMove: (SessionID, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [SidebarReorderPayload.type]), let dragging, dragging != target else { return false }
        let siblings = siblings()
        return siblings.contains(dragging) && siblings.contains(target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropTarget = SidebarDropTarget(sessionID: target, before: info.location.y < 13)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.sessionID == target { dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropTarget = nil; dragging = nil }
        guard validateDrop(info: info), let dragging, let dropTarget, dropTarget.sessionID == target,
              let index = siblings().firstIndex(of: target) else { return false }
        onMove(dragging, dropTarget.before ? index : index + 1)
        return true
    }
}

// MARK: - Parts

/// 縦の案内線（親の段ごと）。
struct SidebarGuides: View {
    let depth: Int

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(1..<max(depth, 1)), id: \.self) { level in
                Rectangle()
                    .fill(DSColor.guide)
                    .frame(width: 1)
                    .offset(x: SidebarRowMetrics.leadingPadding(depth: level) + 5)
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

/// 畳んだ行の要約。状態の記号 9pt ＋ 件数（「◆1 ●1」。11/600/fg2）。未読の完了は accent の点（2026-09-24 ユーザー決定: 記号で出す）。
struct SidebarSummaryText: View {
    let summary: SidebarCollapsedSummary
    var showsCounts = true
    @Environment(\.locale) private var locale

    var body: some View {
        if !summary.isEmpty {
            HStack(spacing: showsCounts ? 6 : 3) {
                ForEach(summary.attention, id: \.kind) { entry in
                    HStack(spacing: 3) {
                        StateGlyph(state: Self.state(for: entry.kind), size: 9)
                        if showsCounts { Text(verbatim: "\(entry.count)") }
                    }
                }
                if summary.unread > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(DSColor.accent).frame(width: 6, height: 6).padding(.horizontal, 2)
                        if showsCounts { Text(verbatim: "\(summary.unread)") }
                    }
                }
            }
            .font(DSFont.meta.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: accessibilityText))
        }
    }

    /// 記号は読み上げないので、「承認待ち 1、未読 1」の文で読む。
    private var accessibilityText: String {
        var parts = summary.attention.map { "\(Self.state(for: $0.kind).localizedLabel(locale: locale)) \($0.count)" }
        if summary.unread > 0 {
            parts.append(String(format: AppLocalizedString.string("未読 %lld", locale: locale), summary.unread))
        }
        return parts.joined(separator: AppLocalizedString.string("、", locale: locale))
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
            .font(DSFont.row)
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

    @Environment(\.locale) private var locale

    var body: some View {
        // 03 F6: 行の高さは変えず、案内は行の下に重なる吹き出しで出す（描くのはサイドバー側）。
        field
            .anchorPreference(key: SidebarRenameHintKey.self, value: .bounds) { SidebarRenameHint(anchor: $0, text: hint) }
    }

    /// 選んだ文字は `--selText` の面（PhloxSidebar の renaming。AppKit の入力欄でないと色を変えられない）。
    private var field: some View {
        DSInlineTextField(
            text: $text,
            placeholder: AppLocalizedString.string("名前", locale: locale),
            onSubmit: { onCommit(true) },
            onCancel: onCancel,
            onEndEditing: { onCommit(false) }
        )
        .padding(.horizontal, 5)
        .frame(height: 20)
        .background(DSColor.fieldBackground, in: RoundedRectangle(cornerRadius: 4))
        // 外側 2pt の accent の輪（box-shadow: 0 0 0 2px）。
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(DSColor.accent, lineWidth: 2).padding(-1))
        .help(Text(hint))
    }
}

struct SidebarRenameHint {
    let anchor: Anchor<CGRect>
    let text: LocalizedStringKey
}

struct SidebarRenameHintKey: PreferenceKey {
    static var defaultValue: SidebarRenameHint? { nil }
    static func reduce(value: inout SidebarRenameHint?, nextValue: () -> SidebarRenameHint?) {
        value = value ?? nextValue()
    }
}

/// 名前変更の欄の 4pt 下に出す吹き出し（PhloxSidebar.dc.html）。幅が足りなければ折り返す。
/// 一覧の末尾で下に収まらないときは欄の上に出す。
struct SidebarRenameHintBubble: View {
    let hint: SidebarRenameHint
    @State private var height: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy[hint.anchor]
            let below = rect.maxY + 4 + height <= proxy.size.height
            bubble(maxWidth: max(0, proxy.size.width - rect.minX - 10))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .frame(height: below ? nil : max(0, rect.minY - 4), alignment: .bottomLeading)
                .offset(x: rect.minX, y: below ? rect.maxY + 4 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bubble(maxWidth: CGFloat) -> some View {
        Text(hint.text)
            .font(DSFont.meta)
            .lineSpacing(2)
            .foregroundStyle(DSColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(DSColor.popoverBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
            .shadow(color: DSShadow.popover.color, radius: DSShadow.popover.radius, y: DSShadow.popover.y)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

/// 右クリックのメニューを開いている行に、ホバーの面と内側 2pt の accent の輪を付ける（03 F2・F4）。
/// macOS ではメニュー内容の onAppear が呼ばれないため、ポインタが乗った行へのクリックでメニューの追跡が始まったら開いたとみなす。
private struct SidebarMenuOpenRing<Menu: View>: ViewModifier {
    @ViewBuilder let menu: () -> Menu
    @State private var isHovering = false
    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .background(isOpen ? DSColor.fillSubtle : .clear, in: RoundedRectangle(cornerRadius: DSRadius.row))
            .overlay {
                if isOpen {
                    RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.accent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onHover { isHovering = $0 }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                // この行へのクリック（右クリック・⋯）で開いたときだけ。キーボードで開いたメインメニューなどは除く。
                let type = NSApp.currentEvent?.type
                if isHovering, type == .rightMouseDown || type == .leftMouseDown { isOpen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                isOpen = false
            }
            .contextMenu { menu() }
    }
}
