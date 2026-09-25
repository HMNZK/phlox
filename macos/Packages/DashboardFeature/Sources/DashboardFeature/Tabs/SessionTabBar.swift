import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 上段のタブ列（02 C1）。プロジェクトのセッションを並べ、右端に共通ターミナル・エージェント管理・＋。
/// 横にあふれたら横スクロールし、見えない位置の対応待ちを右端にまとめて出す（C7）。
struct SessionTabBar: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let sessions: [SessionNode]
    let projectID: ProjectID?
    let hasCommonTerminal: Bool
    let agentConsoleWindowID: String?

    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @State private var tabFrames: [SessionID: CGRect] = [:]
    @State private var viewportWidth: CGFloat = 0

    private nonisolated static let coordinateSpace = "session-tab-bar"

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(sessions, id: \.id) { node in
                            SessionTabButton(
                                node: node,
                                isSelected: !router.commonTerminalSelected && router.selectedSession == node.id,
                                onSelect: { select(node.id) },
                                onClose: { close(node.id) }
                            )
                            .id(node.id)
                            .draggable(Self.dragPayload(node.id))
                            .dropDestination(for: String.self) { items, _ in
                                moveTab(items.first, onto: node.id)
                            }
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named(Self.coordinateSpace))
                            } action: { frame in
                                tabFrames[node.id] = frame
                            }
                        }
                        // 02 C1: ＋はセッションのタブの直後（その右は空き）。
                        newTabButton
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
                .coordinateSpace(.named(Self.coordinateSpace))
                .onChange(of: router.selectedSession) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
            if let summary = hiddenAttention {
                hiddenAttentionBadge(summary)
            }
            if hasCommonTerminal {
                pinnedTab(
                    glyph: ">_",
                    title: "共通ターミナル",
                    isSelected: router.commonTerminalSelected,
                    help: "worktree の外（ホーム）で開くターミナル"
                ) {
                    router.commonTerminalSelected = true
                }
            }
            if let agentConsoleWindowID {
                pinnedTab(
                    glyph: "⚙",
                    title: "エージェント管理",
                    isSelected: false,
                    help: "エージェント管理（⇧⌘,）"
                ) {
                    openWindow(id: agentConsoleWindowID)
                }
            }
        }
        .frame(height: DSLayout.tabBarHeight)
        .background(DSColor.tabBarBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("タブ"))
    }

    private var newTabButton: some View {
        Button {
            router.newTabChooserPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverableIconButtonStyle())
        .disabled(router.selectedSession == nil || router.commonTerminalSelected)
        .help(Text("新しいタブ（⌘T）"))
        .accessibilityLabel(Text("新しいタブ（⌘T）"))
        .padding(.horizontal, DSSpacing.xxs)
    }

    // MARK: - Hidden attention (C7)

    private var hiddenAttention: HiddenAttentionSummary? {
        guard viewportWidth > 0 else { return nil }
        let hidden = sessions.filter { node in
            guard let frame = tabFrames[node.id] else { return false }
            return frame.minX < -1 || frame.maxX > viewportWidth + 1
        }
        return HiddenAttentionSummary.make(hiddenStates: hidden.map(\.tabDisplayState))
    }

    private func hiddenAttentionBadge(_ summary: HiddenAttentionSummary) -> some View {
        // 文言は画面のロケール（アプリ内の言語設定）で引くため Text で組み立てる。
        let label = summary.kind.map { Text(verbatim: Self.state(for: $0).localizedLabel(locale: locale)) }
            ?? Text("対応待ち")
        let text = Text("隠れたタブに \(label) \(summary.count)")
        return Button {
            revealFirstHiddenAttention()
        } label: {
            text
                .font(DSFont.stateLabel)
                .foregroundStyle(summary.kind.map(DSColor.attentionInk) ?? DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.s)
                .frame(height: 22)
                .background(
                    summary.kind.map(DSColor.attentionTint) ?? DSColor.fillSubtle,
                    in: RoundedRectangle(cornerRadius: DSRadius.row)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, DSSpacing.s)
        .help(text)
        .accessibilityLabel(text)
    }

    private static func state(for kind: AttentionKind) -> SessionDisplayState {
        switch kind {
        case .approval: .approval
        case .question: .question
        case .error: .error
        case .stalled: .stalled
        }
    }

    private func revealFirstHiddenAttention() {
        let target = sessions.first { node in
            guard node.tabDisplayState.attentionKind != nil, let frame = tabFrames[node.id] else { return false }
            return frame.minX < -1 || frame.maxX > viewportWidth + 1
        }
        if let target { select(target.id) }
    }

    // MARK: - Actions

    private static let dragPrefix = "phlox-session-tab:"

    private static func dragPayload(_ id: SessionID) -> String {
        dragPrefix + id.rawValue.uuidString
    }

    /// ドラッグで並べ替えた順をプロジェクトごとに保存する。
    private func moveTab(_ payload: String?, onto target: SessionID) -> Bool {
        guard let projectID, let payload, payload.hasPrefix(Self.dragPrefix),
              let uuid = UUID(uuidString: String(payload.dropFirst(Self.dragPrefix.count))) else { return false }
        router.tabs.moveSessionTab(
            SessionID(rawValue: uuid),
            onto: target,
            in: projectID,
            candidates: viewModel.sessionNodes(in: projectID).map(\.id)
        )
        return true
    }

    private func select(_ id: SessionID) {
        router.commonTerminalSelected = false
        router.selectedSession = id
    }

    /// タブだけを閉じる。セッションは止めずサイドバーに残る。
    private func close(_ id: SessionID) {
        guard let projectID else { return }
        let next = router.tabs.closeSessionTab(id, in: projectID, candidates: viewModel.sessionNodes(in: projectID).map(\.id))
        if router.selectedSession == id {
            router.selectedSession = next
            if next == nil { router.selectProject(projectID) }
        }
    }

    private func pinnedTab(
        glyph: String,
        title: LocalizedStringKey,
        isSelected: Bool,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                Text(verbatim: glyph)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(DSColor.textTertiary)
                Text(title)
                    .font(DSFont.auxiliary)
                    .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DSSpacing.m)
            .frame(maxHeight: .infinity)
            .background(isSelected ? DSColor.windowBackground : Color.clear)
            .overlay(alignment: .top) {
                if isSelected { Rectangle().fill(DSColor.accent).frame(height: 2) }
            }
            .overlay(alignment: .leading) { Rectangle().fill(DSColor.separator).frame(width: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 上段のセッションタブ 1 枚。エージェントの頭文字・題名・対応待ちの状態文言・✕。
private struct SessionTabButton: View {
    let node: SessionNode
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.locale) private var locale

    private var state: SessionDisplayState { node.tabDisplayState }

    var body: some View {
        // PhloxTabs.dc.html:148-154: 内容の幅（最大 220）、padding 0 10、間 6。✕ は選択中のタブだけ。
        HStack(spacing: 6) {
            Text(verbatim: node.agentDescriptor.tabInitials)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DSColor.textTertiary)
            Text(node.displayName)
                .font(DSFont.auxiliary.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DSColor.textPrimary : DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if state.attentionKind != nil {
                Text(verbatim: state.localizedLabel(locale: locale))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(state.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            if isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(DSColor.textTertiary)
                        .frame(width: 14, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverableIconButtonStyle())
                .help(Text("タブを閉じる（セッションは残ります）"))
                .accessibilityLabel(Text("タブを閉じる"))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 220, maxHeight: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .top) {
            if isSelected { Rectangle().fill(DSColor.accent).frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(DSColor.separator).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: Text("タブを閉じる"), onClose)
    }

    private var background: Color {
        if isSelected { return DSColor.windowBackground }
        if let kind = state.attentionKind { return DSColor.attentionTint(kind) }
        return .clear
    }

    private var accessibilityText: Text {
        guard state.attentionKind != nil else { return Text(verbatim: node.displayName) }
        return Text("\(node.displayName)、\(state.localizedLabel(locale: locale))")
    }
}

extension SessionNode {
    /// タブ・一覧に出す状態（完了の未読・無応答を含む）。
    var tabDisplayState: SessionDisplayState {
        SessionDisplayState.resolve(displayStatus, hasUnseenCompletion: hasUnseenCompletion, isStalled: isStalled)
    }
}
