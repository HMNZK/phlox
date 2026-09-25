import SwiftUI
import AgentDomain
import DesignSystem
import StructuredChatKit

// 06 Grid のタイルの部品。見出し（状態の文字・内部・タイトル・未読・子タブ・エージェント・番号・✕）と、
// 大きさで入れ替える本文（大・中の一部は会話の列、それ以外は最後の発言と要求の中身）。

/// タイルの大きさ（06 論点 3）。文字は縮めず、出すものを減らす。
public enum GridTileSize: Equatable, Sendable {
    case small
    case medium
    case large

    public init(_ size: CGSize) {
        if size.width < 250 || size.height < 175 {
            self = .small
        } else if size.width < 480 || size.height < 330 {
            self = .medium
        } else {
            self = .large
        }
    }

    /// 会話の列（履歴・返答エリア・入力欄）をそのまま出すか。中は高さ 300pt 以上なら出す（06 のモック）。
    public static func showsConversationColumn(_ size: CGSize) -> Bool {
        switch GridTileSize(size) {
        case .large: true
        case .medium: size.height >= 300
        case .small: false
        }
    }

    /// 見出しに 会話 / 端末 / 変更 を出すか（小では隠し、幅 380pt 以上のチャットのタイルだけ）。
    public static func showsChildTabs(_ size: CGSize) -> Bool {
        GridTileSize(size) != .small && size.width >= 380
    }
}

/// タイルの子タブ（02 C3 のグリッド側）。
public enum GridTileTab: Hashable, CaseIterable, Sendable {
    case conversation
    case terminal
    case changes

    var title: LocalizedStringKey {
        switch self {
        case .conversation: "会話"
        case .terminal: "端末"
        case .changes: "変更"
        }
    }
}

/// タイルの子タブの状態と中身。並びと選択は単体表示の子タブと同じものを使い、中身も単体表示と同じものを外から渡す。
public struct GridTileTabs {
    let selected: (SessionID) -> GridTileTab
    let select: (SessionID, GridTileTab) -> Void
    let content: (SessionID, GridTileTab) -> AnyView

    public init(
        selected: @escaping (SessionID) -> GridTileTab,
        select: @escaping (SessionID, GridTileTab) -> Void,
        content: @escaping (SessionID, GridTileTab) -> AnyView
    ) {
        self.selected = selected
        self.select = select
        self.content = content
    }
}

extension SessionNode {
    /// タイル・一覧に出す状態（完了の未読・無応答を含む）。
    public var gridDisplayState: SessionDisplayState {
        SessionDisplayState.resolve(displayStatus, hasUnseenCompletion: hasUnseenCompletion, isStalled: isStalled)
    }
}

public enum GridTileText {
    /// タイルの読み上げ「タイトル、状態、経過時間、フォーカス中」（06 のモックの aria-label）。
    static func accessibilityLabel(title: String, state: String, elapsed: String?, isFocused: Bool, locale: Locale) -> String {
        var parts = [title, state]
        if let elapsed { parts.append(elapsed) }
        if isFocused { parts.append(AppLocalizedString.string("フォーカス中", locale: locale)) }
        return parts.joined(separator: AppLocalizedString.string("、", locale: locale))
    }

    /// 見出しの状態。対応待ちは「承認待ち · 3分」、無応答も同じ形で黙っている時間（「無応答 · 2分」）、ほかは状態の語だけ。
    public static func stateLabel(state: SessionDisplayState, since: Date?, silence: TimeInterval?, now: Date, locale: Locale) -> String {
        let word = state.localizedLabel(locale: locale)
        if state == .stalled, let silence {
            return "\(word) · \(SessionRelativeTime.label(from: now.addingTimeInterval(-silence), to: now, locale: locale))"
        }
        guard state.attentionKind != nil, let since else { return word }
        return "\(word) · \(SessionRelativeTime.label(from: since, to: now, locale: locale))"
    }
}

// MARK: - 見出し

struct GridTileHeader: View {
    let session: SessionNode
    let tileSize: CGSize
    let number: Int?
    let isInternal: Bool
    let canRemoveFromGrid: Bool
    let tabs: GridTileTabs?
    let onRemoveFromGrid: () -> Void
    let onSelect: () -> Void

    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var size: GridTileSize { GridTileSize(tileSize) }
    private var state: SessionDisplayState { session.gridDisplayState }

    var body: some View {
        let _ = themeID
        HStack(spacing: 7) {
            stateText
            if isInternal {
                Text("内部")
                    .font(.system(size: 10))
                    .foregroundStyle(DSColor.textSecondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.textTertiary, lineWidth: 1))
                    .layoutPriority(1)
            }
            let presentation = SessionTitlePresentation(
                state: session.titleState,
                fallback: SessionViewModel.shortID(for: session.id),
                workspacePath: session.workspacePath
            )
            Text(verbatim: presentation.primary)
                .font(DSFont.dense.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .opacity(isCalm ? 0.8 : 1)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(presentation.helpText)
            if state == .doneUnread {
                Circle()
                    .fill(DSColor.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(Text("未読"))
            }
            if let tabs, session.pty == nil, GridTileSize.showsChildTabs(tileSize) {
                childTabs(tabs)
            }
            if size != .small {
                Text(verbatim: session.agentDescriptor.tabInitials)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.textTertiary)
                    .accessibilityHidden(true)
                if let number, number <= 9 {
                    Text(verbatim: "⌘\(number)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DSColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            Button(action: onRemoveFromGrid) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverableIconButtonStyle())
            .disabled(!canRemoveFromGrid)
            .help(Text("グリッドから外す（⌘W）"))
            .accessibilityLabel(Text("グリッドから外す"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: size == .small ? 28 : 30)
        .background(state.attentionKind.map { DSColor.attentionTint($0) } ?? Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSColor.separator).frame(height: 1)
        }
    }

    /// 起動中・待機・完了は弱い文字、実行中は太字、対応待ちは状態の色（06 論点 1・2）。
    private var isCalm: Bool {
        state.attentionKind == nil && state != .running && state != .doneUnread
    }

    @ViewBuilder
    private var stateText: some View {
        if state == .stalled {
            TimelineView(.periodic(from: .now, by: 1)) { context in label(now: context.date) }
        } else if state.attentionKind != nil, session.statusEnteredAt != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in label(now: context.date) }
        } else {
            label(now: Date())
        }
    }

    private func label(now: Date) -> some View {
        Text(verbatim: GridTileText.stateLabel(
            state: state,
            since: session.statusEnteredAt,
            silence: session.stalledSilence(now: now),
            now: now,
            locale: locale
        ))
        .font(.system(size: 11.5, weight: state.attentionKind != nil || state == .running ? .bold : .medium))
        .monospacedDigit()
        .foregroundStyle(state.attentionKind.map { DSColor.attentionInk($0) } ?? (state == .running ? DSColor.textPrimary : DSColor.textTertiary))
        .lineLimit(1)
        .layoutPriority(2)
    }

    private func childTabs(_ tabs: GridTileTabs) -> some View {
        let selected = tabs.selected(session.id)
        return HStack(spacing: 1) {
            ForEach(GridTileTab.allCases, id: \.self) { tab in
                Button {
                    onSelect()
                    tabs.select(session.id, tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(tab == selected ? DSColor.textPrimary : DSColor.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background {
                            if tab == selected {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(DSColor.background)
                                    .shadow(color: .black.opacity(0.2), radius: 0.75, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(DSColor.segmentTrack, in: RoundedRectangle(cornerRadius: 5))
        .layoutPriority(1)
    }
}

/// 子セッションの親（06 S7「↳ 親: …」）。
struct GridTileParentRow: View {
    let parentName: String

    var body: some View {
        Text("↳ 親: \(parentName)")
            .font(DSFont.meta)
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DSColor.separator).frame(height: 1)
            }
    }
}

// MARK: - 中・小の本文

/// 会話の列を出さない大きさのタイルの本文。最後の発言と、いま求められていること（承認・質問・エラー・無応答・実行中）。
/// 入力はしない。入力・回答するときは「開く」で単体表示へ移る（06 対応表「クリックで大きくして入力」）。
struct GridTileCompactBody: View {
    @Bindable var viewModel: ChatSessionViewModel
    let tileSize: CGSize
    let onOpen: () -> Void

    @Environment(\.locale) private var locale
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    private var isSmall: Bool { GridTileSize(tileSize) == .small }

    private var state: SessionDisplayState {
        SessionDisplayState.resolve(viewModel.displayStatus, hasUnseenCompletion: viewModel.hasUnseenCompletion, isStalled: viewModel.isStalled)
    }

    var body: some View {
        let _ = themeID
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if let last = lastAgentText, !isSmall || state.attentionKind == nil {
                Text(verbatim: last)
                    .font(.system(size: isSmall ? 11.5 : 12))
                    .foregroundStyle(state.attentionKind == nil ? DSColor.textPrimary : DSColor.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            request
        }
        .padding(.horizontal, isSmall ? 9 : 12)
        .padding(.vertical, isSmall ? 7 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var lastAgentText: String? {
        for item in viewModel.transcript.reversed() {
            if case .agentMessage(_, let text, _) = item {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private var pendingQuestion: (requestId: String, questions: [ChatUserQuestion])? {
        for item in viewModel.transcript {
            guard case .userQuestion(_, let requestId, let questions, _, .pending, _) = item,
                  !ChatSessionViewModel.isToolPermissionQuestion(questions) else { continue }
            return (requestId, questions)
        }
        return nil
    }

    /// タイルの中で答えられる質問（1 問・単一選択・伏せ字でない）。それ以外は「開いて回答」。
    static func answerableInTile(_ questions: [ChatUserQuestion]) -> ChatUserQuestion? {
        guard questions.count == 1, let question = questions.first,
              !question.multiSelect, !question.isSecret, !question.options.isEmpty else { return nil }
        return question
    }

    @ViewBuilder
    private var request: some View {
        if let approval = viewModel.currentReplyApproval {
            GridTileApprovalCard(viewModel: viewModel, approval: approval, isSmall: isSmall, onOpen: onOpen)
                .id(approval.id)
        } else if let pending = pendingQuestion {
            card(.question) {
                Text(verbatim: pending.questions.first?.question ?? "")
                    .font(DSFont.auxiliary.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(isSmall ? 1 : 3)
                if !isSmall, let question = Self.answerableInTile(pending.questions) {
                    GridTileQuestionChoices(viewModel: viewModel, requestId: pending.requestId, question: question)
                        .id(pending.requestId)
                } else {
                    Button { onOpen() } label: { Text("開いて回答") }
                        .buttonStyle(ApprovalPrimaryButtonStyle(progress: 1, isArmed: true, compact: true))
                        .font(DSFont.stateLabel)
                }
            }
        } else if case .error(let message) = viewModel.displayStatus {
            card(.error) {
                Text(verbatim: message.components(separatedBy: .newlines).first ?? message)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(DSColor.attentionInk(.error))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button { onOpen() } label: { Text("開く") }
                    .buttonStyle(ApprovalSecondaryButtonStyle(compact: true))
                    .font(.system(size: 11.5))
            }
        } else if viewModel.isStalled {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    stalledText(now: context.date)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await viewModel.turnInterrupt() } } label: { Text("中断") }
                        .buttonStyle(ApprovalSecondaryButtonStyle(compact: true))
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(DSColor.attentionTint(.stalled), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.attentionMark(.stalled), lineWidth: 1))
            }
        } else if viewModel.status == .running {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 7) {
                    Circle()
                        .strokeBorder(DSColor.textSecondary, style: StrokeStyle(lineWidth: 1.6, dash: [1.5, 2]))
                        .frame(width: 12, height: 12)
                    (ThinkingIndicatorCell.detailText(
                        recap: viewModel.thinkingRecap(now: context.date),
                        assessment: viewModel.hangAssessment(now: context.date)
                    ) ?? Text("実行中"))
                        .italic()
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 「無応答 4:12 · Read APNsNotificationBridge.swift」。
    private func stalledText(now: Date) -> Text {
        let clock = Text(verbatim: "\(SessionDisplayState.stalled.localizedLabel(locale: locale)) \(StallClock.text(viewModel.hangAssessment(now: now)?.silence ?? 0))")
        guard let detail = ThinkingIndicatorCell.detailText(recap: viewModel.thinkingRecap(now: now), assessment: viewModel.hangAssessment(now: now)) else { return clock }
        return clock + Text(verbatim: " · ") + detail
    }

    private func card<Content: View>(_ kind: AttentionKind, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(DSColor.attentionTint(kind), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.attentionMark(kind), lineWidth: 1))
    }
}

/// 中タイルの質問の選択肢（06 S3・S5）: 11pt のラジオと「回答を送信」。選んでから送る。
private struct GridTileQuestionChoices: View {
    let viewModel: ChatSessionViewModel
    let requestId: String
    let question: ChatUserQuestion
    @State private var selected: String?

    var body: some View {
        ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
            let isOn = selected == option.label
            Button { selected = option.label } label: {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(isOn ? DSColor.attentionMark(.question) : DSColor.textTertiary, lineWidth: isOn ? 3.5 : 1.2)
                        .frame(width: 11, height: 11)
                    Text(verbatim: option.label)
                        .font(DSFont.auxiliary)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
        Button {
            guard let selected else { return }
            Task { _ = await viewModel.respondToUserQuestion(requestId: requestId, answers: [question.answerKey: [selected]]) }
        } label: { Text("回答を送信") }
            .buttonStyle(ApprovalPrimaryButtonStyle(progress: 1, isArmed: selected != nil, compact: true))
            .font(DSFont.stateLabel)
            .disabled(selected == nil)
    }
}

/// タイルの承認カード（06 S3・S3b・S4）。フォーカスしていないタイルでもそのまま押せる。
/// 出てから 0.5 秒は押せない（返答エリアの承認カードと同じ）。
private struct GridTileApprovalCard: View {
    @Bindable var viewModel: ChatSessionViewModel
    let approval: ReplyApproval
    let isSmall: Bool
    let onOpen: () -> Void

    @State private var isArmed = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isSmall {
                Text(verbatim: ApprovalCard.kindLabel(approval.kind, locale: locale))
                    .font(DSFont.meta.weight(.semibold))
                    .foregroundStyle(DSColor.attentionInk(.approval))
            }
            Text(verbatim: detail)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 5) {
                Button { respond(.accept) } label: { Text("許可") }
                    .buttonStyle(ApprovalPrimaryButtonStyle(progress: isArmed ? 1 : 0, isArmed: isArmed, compact: true))
                    .font(DSFont.stateLabel)
                if isSmall {
                    Button { onOpen() } label: { Text("開く") }
                        .buttonStyle(ApprovalSecondaryButtonStyle(compact: true))
                } else {
                    if approval.supportsSessionScope {
                        Button { respond(.acceptForSession) } label: { Text("このセッション中は許可") }
                            .buttonStyle(ApprovalSecondaryButtonStyle(compact: true))
                    }
                    Button { respond(.decline) } label: { Text("拒否") }
                        .buttonStyle(ApprovalSecondaryButtonStyle(compact: true))
                }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(DSColor.attentionTint(.approval), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.attentionMark(.approval), lineWidth: 1))
        .task(id: approval.id) {
            viewModel.markApprovalPresented(approval.id)
            isArmed = viewModel.isApprovalArmed(approval.id)
            guard !isArmed else { return }
            try? await Task.sleep(for: .seconds(ReplyApproval.armDelay))
            isArmed = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("承認待ち · \(ApprovalCard.kindLabel(approval.kind, locale: locale))"))
    }

    private var detail: String {
        switch approval.kind {
        case .command: "$ \(approval.subject ?? "")"
        case .fileChange: approval.files.first?.path ?? approval.subject ?? ""
        case .permissions, .tool: approval.subject ?? ""
        }
    }

    private func respond(_ decision: ApprovalDecision) {
        guard isArmed else { return }
        Task { await viewModel.respond(to: approval, decision: decision) }
    }
}
