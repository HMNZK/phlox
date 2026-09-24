import AppKit
import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// ツールバー右の「対応待ち n」。押すと待ち時間の長い順の一覧を開く（⌥⌘J）。
/// 対応待ちが無いときは押せない（一覧の空表示はデザインに無いため出さない）。
struct AttentionButton: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter
    let density: ToolbarDensity

    @Environment(\.locale) private var locale

    var body: some View {
        let count = viewModel.attentionEntries.count
        Button {
            router.attentionListPresented.toggle()
        } label: {
            // 01 D: full は記号＋文言＋件数、compact は文言＋件数、minimal は件数だけ。
            // 0 件の見本は無い。件数の丸を出さず、文言（minimal は記号）を淡くして押せなくする。
            HStack(spacing: 7) {
                if density == .full || (density == .minimal && count == 0) {
                    HStack(spacing: 3) {
                        ForEach([SessionDisplayState.approval, .question, .error, .stalled], id: \.self) {
                            StateGlyph(state: $0, size: 9)
                        }
                    }
                    .opacity(count > 0 ? 1 : 0.45)
                }
                if density != .minimal {
                    Text("対応待ち")
                        .font(DSFont.auxiliary.weight(.medium))
                        .foregroundStyle(count > 0 ? DSColor.textPrimary : DSColor.textTertiary)
                }
                if count > 0 {
                    CountBadge(count: count)
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, count > 0 ? 6 : 9)
            .frame(height: 26)
            .background(
                router.attentionListPresented && count > 0 ? DSColor.fillSelected : DSColor.controlBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.controlBorder, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .help(Text("対応待ち \(count) 件（⌥⌘J で一覧、⌘J で次へ）"))
        .accessibilityLabel(Text("対応待ち \(count) 件（⌥⌘J で一覧、⌘J で次へ）"))
        .popover(isPresented: listBinding(count: count), arrowEdge: .bottom) {
            // ツールバーから開くポップオーバーはアプリ内の言語設定を受け継がないので渡し直す。
            AttentionListPopover(viewModel: viewModel, router: router)
                .environment(\.locale, locale)
        }
    }

    /// 0 件のときは ⌥⌘J でも開かない。
    private func listBinding(count: Int) -> Binding<Bool> {
        Binding(
            get: { router.attentionListPresented && count > 0 },
            set: { router.attentionListPresented = $0 }
        )
    }
}

/// 対応待ちの一覧（01 E1）。開いた直後は 1 行目にキーボードフォーカスを置く。
/// ↑↓ で移動、↩ でそのセッションを開く（表示モードは変えない）、⌥⌘↩ で許可。
struct AttentionListPopover: View {
    @Bindable var viewModel: DashboardViewModel
    @Bindable var router: AppRouter

    @FocusState private var focusedID: SessionID?
    @Environment(\.locale) private var locale

    private var rows: [(entry: AttentionEntry, node: SessionNode)] {
        viewModel.attentionEntries.compactMap { entry in
            viewModel.sessionNode(id: entry.id).map { (entry, $0) }
        }
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            header(count: rows.count)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rows, id: \.entry.id) { row in
                        AttentionRow(
                            entry: row.entry,
                            node: row.node,
                            projectName: projectName(for: row.node),
                            isFocused: focusedID == row.entry.id,
                            onOpen: { open(row.entry.id) },
                            onDecide: { decide($0, for: row.node) },
                            onInterrupt: { interrupt(row.node) }
                        )
                        .focusable()
                        .focused($focusedID, equals: row.entry.id)
                        .focusEffectDisabled()
                    }
                }
            }
            .frame(maxHeight: 460)
            footer
        }
        .padding(6)
        .frame(width: 400)
        .background(DSColor.popoverBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("対応待ち"))
        .onAppear { focusedID = rows.first?.entry.id }
        .onKeyPress(.downArrow) { moveFocus(by: 1, in: rows) }
        .onKeyPress(.upArrow) { moveFocus(by: -1, in: rows) }
        .onKeyPress(.return, phases: .down) { press in
            guard let id = focusedID, let row = rows.first(where: { $0.entry.id == id }) else { return .ignored }
            if press.modifiers.isSuperset(of: [.command, .option]) {
                decide(.accept, for: row.node)
            } else {
                open(id)
            }
            return .handled
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: DSSpacing.s) {
            Text("対応待ち")
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text("\(count) 件・待ち時間の長い順")
                .font(DSFont.auxiliary)
                .foregroundStyle(DSColor.textSecondary)
            Spacer(minLength: 0)
            Text(verbatim: "⌥⌘J")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var footer: some View {
        let unseen = viewModel.unseenCompletionNodes
        VStack(alignment: .leading, spacing: 0) {
            if let first = unseen.first {
                Rectangle().fill(DSColor.separator).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
                HStack(spacing: 8) {
                    Circle().fill(DSColor.accent).frame(width: 6, height: 6).padding(.horizontal, 3)
                    Text("完了・未読 \(unseen.count) 件 — \(first.displayName)")
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let at = first.statusEnteredAt {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(SidebarRelativeTime.label(from: at, to: context.date, locale: locale))
                                .font(DSFont.auxiliary)
                                .foregroundStyle(DSColor.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            Rectangle().fill(DSColor.separator).frame(height: 1)
            HStack(spacing: 14) {
                Text("⌘J 次の対応待ちへ")
                Text("↑↓ 移動")
                Text("↩ 開く")
                Text("⌥⌘↩ 許可")
            }
            .font(DSFont.meta)
            .foregroundStyle(DSColor.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func projectName(for node: SessionNode) -> String? {
        node.projectID.flatMap { id in viewModel.projects.first { $0.id == id }?.name }
    }

    private func moveFocus(by offset: Int, in rows: [(entry: AttentionEntry, node: SessionNode)]) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.entry.id == focusedID } ?? -offset
        let next = min(max(current + offset, 0), rows.count - 1)
        focusedID = rows[next].entry.id
        return .handled
    }

    /// 表示モードは変えずにそのセッションを選ぶ（グリッドではそのタイルがフォーカスになる）。
    private func open(_ id: SessionID) {
        // 一覧を閉じるとメインウィンドウの入力欄がフォーカスを取り戻し、グリッドではそのタイルが
        // 選択を上書きする。先にフォーカスを外してから選ぶ。
        NSApp.mainWindow?.makeFirstResponder(nil)
        router.selectedSession = id
        router.attentionListPresented = false
    }

    /// チャット型の承認待ちだけ一覧から許可・拒否できる。
    private func decide(_ decision: ApprovalDecision, for node: SessionNode) {
        guard case .appServer(let chat) = node, let approval = chat.pendingApprovals.first else { return }
        Task { await chat.respondToApproval(approval.id, decision: decision) }
    }

    /// 無応答のチャット型を一覧から中断する（01 E1）。
    private func interrupt(_ node: SessionNode) {
        guard case .appServer(let chat) = node else { return }
        Task { await chat.turnInterrupt() }
    }
}

private struct AttentionRow: View {
    let entry: AttentionEntry
    let node: SessionNode
    let projectName: String?
    let isFocused: Bool
    let onOpen: () -> Void
    let onDecide: (ApprovalDecision) -> Void
    let onInterrupt: () -> Void

    @Environment(\.locale) private var locale

    private var state: SessionDisplayState { node.tabDisplayState }

    /// 記号 12 ＋ 間 8 ＋ 頭文字 16 ＋ 間 8。2 行目以降を題名の頭に揃える。
    private static let indent: CGFloat = 44

    /// 「プロジェクト · 花名 · エージェント名」。
    private var subline: String {
        let flower = SessionTitlePresentation(
            state: node.titleState,
            fallback: SessionViewModel.shortID(for: node.id),
            workspacePath: node.workspacePath
        ).secondary
        return [projectName, flower, node.agentDescriptor.displayName].compactMap { $0 }.joined(separator: " · ")
    }

    private var canDecide: Bool {
        if case .appServer(let chat) = node { return !chat.pendingApprovals.isEmpty }
        return false
    }

    private func detail(now: Date) -> String? {
        // 01 E1: 無応答は「無応答 4:12」を中身の行に出す。
        if state == .stalled, let silence = node.stalledSilence(now: now) {
            return "\(state.localizedLabel(locale: locale)) \(StallClock.text(silence))"
        }
        switch node.displayStatus {
        case .awaitingApproval(let prompt): return prompt.isEmpty ? nil : prompt
        case .error(let message): return message.isEmpty ? nil : message
        default: return nil
        }
    }

    var body: some View {
        // 無応答の経過は 1 秒ごと、それ以外は待ち時間の分表示に合わせて 1 分ごと。
        TimelineView(.periodic(from: .now, by: state == .stalled ? 1 : 60)) { context in
            let elapsed = entry.since.map { SidebarRelativeTime.label(from: $0, to: context.date, locale: locale) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StateGlyph(state: state)
                    AgentInitialTile(descriptor: node.agentDescriptor)
                    Text(node.displayName)
                        .font(DSFont.row.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: DSSpacing.s)
                    StatusLabel(state: state)
                    if let elapsed {
                        Text(elapsed)
                            .font(DSFont.meta)
                            .foregroundStyle(DSColor.textTertiary)
                            .monospacedDigit()
                    }
                }
                Group {
                    Text(subline)
                        .font(DSFont.meta)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                    if let detail = detail(now: context.date) {
                        Text(detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: 5))
                    }
                    actions
                }
                .padding(.leading, Self.indent)
            }
            // 01 E1: 行は面も枠も無い。フォーカス中の 1 行だけホバーの面と内側 2pt の accent の輪。
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .background(isFocused ? DSColor.fillSubtle : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(DSColor.accent, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(accessibilityText(now: context.date)))
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if state == .approval, canDecide {
                Button("許可") { onDecide(.accept) }
                    .buttonStyle(AttentionActionButtonStyle(isPrimary: true))
                Button("拒否") { onDecide(.decline) }
                    .buttonStyle(AttentionActionButtonStyle(isPrimary: false))
            } else if state == .question {
                Button("回答する…", action: onOpen)
                    .buttonStyle(AttentionActionButtonStyle(isPrimary: true))
            } else if state == .stalled {
                Button("中断", action: onInterrupt)
                    .buttonStyle(AttentionActionButtonStyle(isPrimary: false))
            }
            Button("開く", action: onOpen)
                .buttonStyle(AttentionActionButtonStyle(isPrimary: false))
        }
    }

    /// 「状態、タイトル、プロジェクト、8 分前から」。経過時間は表示言語の相対表現で読む。
    private func accessibilityText(now: Date) -> String {
        let parts = [state.localizedLabel(locale: locale), node.displayName, projectName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: AppLocalizedString.string("、", locale: locale))
        guard let since = entry.since else { return parts }
        let relative = since.formatted(
            Date.RelativeFormatStyle(presentation: .numeric, unitsStyle: .wide, locale: locale)
        )
        return String(format: AppLocalizedString.string("%@、%@から", locale: locale), parts, relative)
    }
}

/// 一覧の行の小さなボタン。主操作だけ accentFill の面に白文字。
private struct AttentionActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? Color.white : DSColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                isPrimary ? DSColor.accentFill : DSColor.controlBackground,
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(DSColor.controlBorder, lineWidth: 0.5)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
