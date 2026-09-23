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
            HStack(spacing: DSSpacing.xs) {
                if density != .minimal {
                    Text("対応待ち")
                        .font(DSFont.auxiliary.weight(.medium))
                        .foregroundStyle(count > 0 ? DSColor.textPrimary : DSColor.textTertiary)
                }
                if count > 0 {
                    CountBadge(count: count)
                } else if density == .minimal {
                    Text("0")
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(.horizontal, DSSpacing.s)
            .frame(height: 28)
            .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: DSRadius.row))
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
                VStack(spacing: DSSpacing.xs) {
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
                .padding(DSSpacing.s)
            }
            .frame(maxHeight: 460)
            footer
        }
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
        .padding(.horizontal, DSSpacing.m)
        .padding(.top, DSSpacing.m)
        .padding(.bottom, DSSpacing.xs)
    }

    @ViewBuilder
    private var footer: some View {
        let unseen = viewModel.unseenCompletionNodes
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            if let first = unseen.first {
                Divider()
                Text("完了・未読 \(unseen.count) 件 — \(first.displayName)")
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, DSSpacing.m)
            }
            Divider()
            Text("⌘J 次の対応待ちへ　↑↓ 移動　↩ 開く　⌥⌘↩ 許可")
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .padding(.horizontal, DSSpacing.m)
                .padding(.bottom, DSSpacing.s)
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
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.s) {
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
                Text([projectName, node.agentDescriptor.displayName].compactMap { $0 }.joined(separator: " · "))
                    .font(DSFont.meta)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                if let detail = detail(now: context.date) {
                    Text(detail)
                        .font(DSFont.monoCaption)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, DSSpacing.s)
                        .padding(.vertical, DSSpacing.xxs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: DSRadius.s))
                }
                actions
            }
            .padding(DSSpacing.s)
            .background(DSColor.cardBackground, in: RoundedRectangle(cornerRadius: DSRadius.attention))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.attention)
                    .strokeBorder(isFocused ? DSColor.accent : DSColor.separator, lineWidth: isFocused ? 2 : 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(accessibilityText(now: context.date)))
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: DSSpacing.xs) {
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
            .font(DSFont.auxiliary.weight(isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? Color.white : DSColor.textPrimary)
            .padding(.horizontal, DSSpacing.s)
            .frame(height: 24)
            .background(
                isPrimary ? DSColor.accentFill : DSColor.fieldBackground,
                in: RoundedRectangle(cornerRadius: DSRadius.s)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.separator)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
