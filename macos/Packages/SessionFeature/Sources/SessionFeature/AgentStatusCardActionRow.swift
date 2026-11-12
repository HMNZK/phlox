import SwiftUI
import StructuredChatKit
import DesignSystem

// エージェント状態カードの作業の行（見本 10-Anatomy「作業の行」、要件 §4.4）。
// 1 行は「種類のアイコン・何をしたか・所要時間」。開くと今のツールカードの中身（差分・コマンド出力）を出す（FR-13）。
// サブエージェントは開けない（FR-14）。作業の行にスピナーは出さない（ADR 0227）。実行中は薄い文字と「〜中」で表す。

extension AgentStatusAction {
    /// 開けるか。サブエージェントは中身を見せない。
    var isExpandable: Bool {
        if case .subAgent = label { return false }
        return true
    }

    func spokenLabel(now: Date? = nil, locale: Locale, bundle: Bundle = .main) -> String {
        let subject = (isRunning ? nil : label.singleFile) ?? text(locale: locale, bundle: bundle)
        var parts: [String]
        if case .subAgent = label { parts = [subject] }
        else { parts = [AppLocalizedString.string(label.spokenKindKey, locale: locale, bundle: bundle), subject] }
        if let duration = now.flatMap({ elapsed(at: $0) }) ?? duration {
            parts.append(AgentStatusDurationFormat.spoken(duration, locale: locale, bundle: bundle, fractional: true))
        }
        if isExpandable { parts.append(AppLocalizedString.string("展開できます", locale: locale, bundle: bundle)) }
        return AgentStatusSpeech.join(parts, locale: locale)
    }
}

struct AgentStatusActionRow: View {
    let action: AgentStatusAction
    let scale: CGFloat
    let isTimelineVisible: Bool
    var runtime: RuntimeStatusCardPresentation?
    private let startsOpen: Bool
    @State private var localIsOpen: Bool
    @Binding private var boundIsOpen: Bool?
    private let hasOpenBinding: Bool
    private var isOpen: Bool {
        get { boundIsOpen ?? localIsOpen }
        nonmutating set {
            if hasOpenBinding { boundIsOpen = newValue }
            else { localIsOpen = newValue }
        }
    }
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @State private var isInViewHierarchy = false
    @State private var isInViewport = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    init(action: AgentStatusAction, scale: CGFloat, isTimelineVisible: Bool, startsOpen: Bool = false, runtime: RuntimeStatusCardPresentation? = nil, openBinding: Binding<Bool>? = nil) {
        self.action = action
        self.scale = scale
        self.isTimelineVisible = isTimelineVisible
        self.runtime = runtime
        self.startsOpen = startsOpen
        _localIsOpen = State(initialValue: startsOpen)
        hasOpenBinding = openBinding != nil
        if let openBinding {
            _boundIsOpen = Binding<Bool?>(get: { openBinding.wrappedValue },
                set: { if let value = $0 { openBinding.wrappedValue = value } })
        } else { _boundIsOpen = .constant(nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if action.isRunning, action.startedAt != nil {
                TimelineView(HangStatusTimelineSchedule(isVisible: isTimelineVisible)) { context in
                    header(now: context.date)
                }
            } else {
                header(now: nil)
            }
            if isOpen, action.isExpandable {
                if let runtime {
                    runtimeDetail(runtime)
                } else { detail }
            }
        }
        .accessibilityIdentifier("AgentStatusCard.action.\(action.id)")
        .onAppear { isInViewHierarchy = true }
        .onDisappear { isInViewHierarchy = false }
        .onViewportVisibilityChange { isInViewport = $0 }
        .onChange(of: startsOpen, initial: true) { _, shouldOpen in if shouldOpen { isOpen = true } }
    }

    @ViewBuilder
    private func header(now: Date?) -> some View {
        if action.isExpandable {
            Button { isOpen.toggle() } label: { rowContent(now: now) }
                .buttonStyle(.plain)
                .focused($isFocused)
                .onHover { isHovered = $0 }
                .accessibilityLabel(Text(verbatim: action.spokenLabel(now: now, locale: locale, bundle: bundle)))
                .accessibilityValue(Text(AppLocalizedString.string(isOpen ? "展開中" : "折りたたみ中", locale: locale, bundle: bundle)))
        } else {
            rowContent(now: now)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: action.spokenLabel(now: now, locale: locale, bundle: bundle)))
        }
    }

    private func rowContent(now: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.label.symbolName)
                .font(.system(size: 12 * scale))
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: AgentStatusCardLayout.actionIconSize)
                .accessibilityHidden(true)
            actionLabel
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isFileAction {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(isHovered || isFocused ? DSColor.chatTextPrimary : DSColor.textTertiary)
                    .opacity(isOpen || isHovered || isFocused ? 1 : 0)
                    .frame(width: 10)
                    .accessibilityHidden(true)
            }
            if let duration = now.flatMap({ action.elapsed(at: $0) }) ?? action.duration {
                Text(verbatim: AgentStatusDurationFormat.action(duration))
                    .font(.system(size: 11.5 * scale))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textTertiary)
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: AgentStatusCardLayout.actionRowHeight * scale)
        .background(isOpen || (isFileAction && (isHovered || isFocused)) ? DSColor.fillSubtle : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
    }

    private var font: Font {
        if case .command = action.label { return .system(size: 12 * scale, design: .monospaced) }
        return .system(size: 12.5 * scale)
    }

    private var isFileAction: Bool {
        switch action.label {
        case .edit, .editFiles, .write: true
        default: false
        }
    }

    private var isShimmerAction: Bool {
        switch action.label {
        case .command, .run, .edit, .editFiles, .write: true
        default: false
        }
    }

    private var isAnimationVisible: Bool {
        isTimelineVisible && action.isRunning && ThinkingAnimationModel.isTimelineVisible(
            isInViewHierarchy: isInViewHierarchy, isInTranscriptViewport: isInViewport, scenePhase: scenePhase)
    }

    @ViewBuilder
    private var actionLabel: some View {
        if case .subAgent = action.label {
            AgentStatusSubAgentLabel(label: action.label, pointSize: 12.5 * scale,
                isRunning: action.isRunning, isAnimationVisible: isAnimationVisible)
        } else if action.isRunning && isShimmerAction {
            ShimmerTextView(text: action.text(locale: locale, bundle: bundle), font: font,
                pointSize: (isCommand ? 12 : 12.5) * scale, color: DSColor.chatTextPrimary,
                isVisible: isAnimationVisible, style: isCommand ? .command : .file)
        } else {
            label
        }
    }

    private var isCommand: Bool {
        if case .command = action.label { true } else { false }
    }

    private var label: Text {
        let text = action.text(locale: locale, bundle: bundle)
        let body = DSColor.chatTextSecondary
        if action.isRunning { return Text(verbatim: text).foregroundStyle(DSColor.textTertiary) }
        guard let emphasis = action.label.emphasis, let range = text.range(of: emphasis) else {
            return Text(verbatim: text).foregroundStyle(body)
        }
        return Text(verbatim: String(text[..<range.lowerBound])).foregroundStyle(body)
            + Text(verbatim: emphasis).foregroundStyle(DSColor.chatTextPrimary)
            + Text(verbatim: String(text[range.upperBound...])).foregroundStyle(body)
    }

    private func runtimeDetail(_ runtime: RuntimeStatusCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let page = runtime.cache.actions[action.id] {
                ForEach(page.items, id: \.id) { reference in
                    RuntimeChatItemReferenceView(reference: reference, viewModel: runtime.viewModel,
                        isActionDetail: true, actionScale: scale, actions: runtime.itemActions)
                }
                if page.nextCursor != nil {
                    Button("さらに表示") { runtime.loadAction(action.id, next: true) }
                }
                if runtime.cache.actionPageOffsets[action.id, default: 0] > 0 {
                    Button("先頭の詳細に戻る") {
                        runtime.loadAction(action.id)
                    }
                    .font(DSFont.meta)
                }
            } else {
                Button("詳細を読み込む") { runtime.loadAction(action.id) }
                    .font(DSFont.meta)
                    .accessibilityIdentifier("AgentStatusCard.reloadActionItems.\(action.id)")
            }
        }
        .padding(.leading, AgentStatusCardLayout.textIndent)
        .padding(.vertical, 8 * scale)
        .task(id: runtime.contentVersion) {
            if runtime.cache.actions[action.id] == nil { runtime.loadAction(action.id) }
        }
    }

    /// 開いた中身。今のセルの部品を再利用する（コマンドの出力・ファイルの差分）。
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(action.items) { item in
                switch item {
                case .commandExecution(_, let command, let output, _, _, _):
                    AgentStatusCommandDetail(command: command, output: output, scale: scale)
                case .fileChange(let id, let changes, let timestamp, _):
                    FileChangeCell(changes: changes, timestamp: timestamp, itemID: id, startsExpanded: true)
                default:
                    EmptyView()
                }
            }
        }
        .padding(.leading, AgentStatusCardLayout.textIndent)
        .padding(.vertical, 8 * scale)
    }
}

/// 担当種別・状態は固定し、長い依頼内容だけを省略する。
struct AgentStatusSubAgentLabel: View {
    let label: AgentStatusAction.Label
    var pointSize: CGFloat = 12.5
    var isRunning = false
    var isAnimationVisible = false
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var bundle

    var body: some View {
        if case .subAgent(let description, let type, let status) = label {
            let subject = "· " + (description.isEmpty
                ? UIWording.text(.missingSubAgentDescription, languageCode: locale.language.languageCode?.identifier ?? "ja")
                : description)
            HStack(spacing: 4) {
                Text("サブエージェント").fixedSize()
                Group {
                    if isRunning {
                        ShimmerTextView(text: subject, font: .system(size: pointSize), pointSize: pointSize,
                            color: DSColor.chatTextPrimary, isVisible: isAnimationVisible, style: .file)
                    } else {
                        Text(verbatim: subject)
                    }
                }
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                if !type.isEmpty { Text(verbatim: "· " + type).lineLimit(1).layoutPriority(-2) }
                Text(verbatim: "· " + AgentStatusAction.Label.subAgentStatusText(status, locale: locale, bundle: bundle))
                    .fixedSize()
            }
            .foregroundStyle(DSColor.chatTextSecondary)
        }
    }
}

/// コマンドを開いた中身: 「$ コマンド」と終了コード、その下に出力（見本 `.wd`）。
struct AgentStatusCommandDetail: View {
    let command: String?
    let output: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: "$ \(command ?? "")")
                    .font(.system(size: 11.5 * scale, design: .monospaced))
                    .foregroundStyle(DSColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = CommandExitCode.badge(for: output) {
                    badge.text
                        .font(.system(size: 11 * scale, weight: badge.weight))
                        .foregroundStyle(badge.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Rectangle().fill(DSColor.separator).frame(height: 1)
                CommandCardOutput(output: output)
            }
        }
        .background(DSColor.chatBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(DSColor.separator, lineWidth: 1)
        }
    }
}
