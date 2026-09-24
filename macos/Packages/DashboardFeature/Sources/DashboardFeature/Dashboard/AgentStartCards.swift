import SwiftUI
import AgentDomain
import DesignSystem
import SessionFeature

/// 空状態カードで選べる起動モード（task-1 契約面）。
enum AgentStartCardMode: Equatable {
    case chat
    case terminal

    var backend: SessionBackend {
        self == .chat ? .appServer : .pty
    }

    var label: String {
        switch self {
        case .chat: "チャット"
        case .terminal: "ターミナル"
        }
    }
}

/// 空状態のエージェント選択カードのモデル（task-1 契約面）。
struct AgentStartCard: Equatable, Identifiable {
    let kind: AgentKind
    var id: AgentKind { kind }
}

enum AgentStartCardsModel {
    /// 利用可能な CLI（`DashboardViewModel.availableAgentKinds`）からカード列を作る（順序保持）。
    static func cards(available: [AgentKind]) -> [AgentStartCard] {
        available.map { AgentStartCard(kind: $0) }
    }

    static func modes(for descriptor: AgentDescriptor) -> [AgentStartCardMode] {
        descriptor.supportsStructuredChat ? [.chat, .terminal] : [.terminal]
    }
}

/// カード選択から `spawnNewSessionUsingDefaultProject` への配線。
enum AgentStartCardSelection {
    @MainActor
    static func spawnNewSession(
        kind: AgentKind,
        viewModel: DashboardViewModel,
        selectedSessionID: SessionID?,
        selectedProjectID: ProjectID? = nil
    ) async throws -> SessionID {
        try await viewModel.spawnNewSessionUsingDefaultProject(
            kind: kind,
            selectedSessionID: selectedSessionID,
            selectedProjectID: selectedProjectID
        )
    }
}

/// 起動カード 1 枚分の表示データ（08 S3・S4）。未検出の種別も元の位置に残す。
struct AgentStartEntry: Identifiable, Equatable {
    let descriptor: AgentDescriptor
    /// 起動時に解決した実行ファイル。nil は未検出。
    let binaryPath: String?
    /// 最後に使ったモデル。nil は「CLI の既定」。
    var model: String? = nil
    /// 権限の初期値。nil は「CLI の既定」。
    var permission: String? = nil

    var id: String { descriptor.ref.id }
    var isDetected: Bool { binaryPath != nil }
}

enum AgentStartEntries {
    /// Claude Code → 組込の残り → カスタムの順（カタログの並び）。未検出も除かない。
    static func make(descriptors: [AgentDescriptor], binaryPath: (AgentRef) -> String?) -> [AgentStartEntry] {
        descriptors.map { AgentStartEntry(descriptor: $0, binaryPath: binaryPath($0.ref)) }
    }

    /// 起動時に渡す権限の初期値。アプリが決めていない種別・設定は nil（CLI の既定）。
    static func permission(ref: AgentRef, fullAccess: Bool, languageCode: String) -> String? {
        func title(_ agent: UIWording.PermissionAgent, _ kind: UIWording.PermissionKind, _ value: String) -> String {
            UIWording.permission(agent: agent, kind: kind, value: value, languageCode: languageCode).title
        }
        switch ref {
        case .builtin(.claudeCode):
            return fullAccess ? title(.claude, .claudePermissionMode, "bypassPermissions") : nil
        case .builtin(.codex):
            let approval = title(.codex, .codexApprovalPolicy, fullAccess ? "never" : "on-request")
            let sandbox = title(.codex, .codexSandboxMode, fullAccess ? "danger-full-access" : "workspace-write")
            return approval + " · " + sandbox
        case .builtin(.cursor):
            return fullAccess ? title(.cursor, .cursorApprovalMode, "unrestricted") : nil
        default:
            return nil
        }
    }

    /// 最後に使ったモデルと推論の強さ。
    static func model(_ settings: LastUsedChatSettings?) -> String? {
        guard let model = settings?.model else { return nil }
        guard let effort = settings?.effort else { return model }
        return model + " · " + effort
    }
}

struct AgentStartCardsView: View {
    let cards: [AgentStartCard]
    let isCreating: Bool
    let onSelect: (AgentKind, SessionBackend) -> Void
    var onLayoutDecision: ((Bool) -> Void)? = nil
    /// 未検出・カスタムを含む表示データ。nil は `cards`（検出済みの組込）だけで描く。
    var entries: [AgentStartEntry]? = nil
    /// カスタム種別も起動できる選択口。nil は `onSelect` に組込の種別で渡す。
    var onSelectRef: ((AgentRef, SessionBackend) -> Void)? = nil
    /// 起動中の種別（08 S5: そのカードに「起動しています…」、ほかは淡く）。
    var creatingRef: AgentRef? = nil
    /// カード列の上に出すプロジェクトの見出し。
    var header: AgentStartProjectHeader? = nil
    /// ↩ で起動する開き方（設定 > 一般 の既定の開き方）。
    var defaultBackend: DefaultSessionBackendPreference = .chat

    @Environment(\.locale) private var locale
    @FocusState private var focused: Bool
    @State private var keyboardIndex = 0

    private var displayed: [AgentStartEntry] {
        entries ?? cards.map { card in
            let descriptor = AgentRegistry.descriptor(for: card.kind)
            return AgentStartEntry(descriptor: descriptor, binaryPath: descriptor.binaryName)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            content(availableWidth: proxy.size.width)
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        let stackVertically = AgentStartCardsLayoutPolicy.shouldStackVertically(
            availableWidth: availableWidth,
            cardCount: displayed.count
        )

        VStack(alignment: .leading, spacing: DSSpacing.l) {
            if let header {
                header
            }
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                Text("新しいセッションを始める")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(String(format: AppLocalizedString.string("1–%lld で選択", locale: locale), displayed.count)
                    + " · " + NewSessionKeys.hint(default: defaultBackend, locale: locale))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textTertiary)
            }

            cardRow(stackVertically: stackVertically, availableWidth: availableWidth)

            Text("モデルはこの種別で最後に使った設定を引き継ぎます。起動後に入力欄の下で変えられます。既定の開き方（チャット / ターミナル）は 設定 > 一般 で変えられます。")
                .font(.system(size: 11.5))
                .foregroundStyle(DSColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DSSpacing.l)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let number = Int(press.characters), number >= 1, number <= displayed.count else { return .ignored }
            keyboardIndex = number - 1
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { press in
            guard !displayed.isEmpty else { return .ignored }
            let step = (press.key == .leftArrow || press.key == .upArrow) ? -1 : 1
            keyboardIndex = (keyboardIndex + step + displayed.count) % displayed.count
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard displayed.indices.contains(keyboardIndex) else { return .ignored }
            let entry = displayed[keyboardIndex]
            let mode = NewSessionKeys.mode(
                default: defaultBackend,
                option: press.modifiers.contains(.option),
                supportsChat: entry.descriptor.supportsStructuredChat
            )
            start(entry, mode: mode)
            return .handled
        }
        .background {
            LayoutDecisionReporter(
                stacksVertically: stackVertically,
                onLayoutDecision: onLayoutDecision
            )
        }
    }

    /// 横並びのときの列数。ボタン 2 つが切れずに入る幅（comfortableCardWidth）を目安に折り返す
    /// （08 S5: 広ければ 4 列、狭ければ 2 列）。縦積みへの切替は凍結済みの AgentStartCardsLayoutPolicy に従う。
    static func columnCount(availableWidth: CGFloat, cardCount: Int) -> Int {
        let usable = min(availableWidth, 920) - AgentStartCardsLayoutPolicy.containerHorizontalPadding * 2
        let spacing = AgentStartCardsLayoutPolicy.interCardSpacing
        let fitting = Int((usable + spacing) / (comfortableCardWidth + spacing))
        return max(1, min(cardCount, 4, fitting))
    }

    static let comfortableCardWidth: CGFloat = 200

    @ViewBuilder
    private func cardRow(stackVertically: Bool, availableWidth: CGFloat) -> some View {
        if stackVertically {
            ScrollView {
                VStack(spacing: DSSpacing.m) {
                    cardButtons
                }
            }
        } else {
            let columns = Self.columnCount(availableWidth: availableWidth, cardCount: displayed.count)
            // 高さは中身に合わせ、同じ行のカードは一番高いものに揃える。
            Grid(horizontalSpacing: DSSpacing.m, verticalSpacing: DSSpacing.m) {
                ForEach(Array(stride(from: 0, to: displayed.count, by: columns)), id: \.self) { start in
                    GridRow {
                        ForEach(start..<min(start + columns, displayed.count), id: \.self) { index in
                            cardButton(index)
                        }
                        ForEach(0..<(columns - min(columns, displayed.count - start)), id: \.self) { _ in
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cardButtons: some View {
        ForEach(displayed.indices, id: \.self) { index in
            cardButton(index)
        }
    }

    private func cardButton(_ index: Int) -> some View {
        let entry = displayed[index]
        return AgentStartCardButton(
            entry: entry,
            number: index + 1,
            isDisabled: isCreating,
            isCreating: creatingRef == entry.descriptor.ref,
            isKeyboardSelected: focused && index == keyboardIndex,
            onSelect: { mode in
                keyboardIndex = index
                start(entry, mode: mode)
            }
        )
    }

    private func start(_ entry: AgentStartEntry, mode: AgentStartCardMode) {
        guard entry.isDetected, !isCreating else { return }
        if let onSelectRef {
            onSelectRef(entry.descriptor.ref, mode.backend)
        } else if case .builtin(let kind) = entry.descriptor.ref {
            onSelect(kind, mode.backend)
        }
    }
}

/// カード列の上のプロジェクト見出し（08 S3・S4: 名前・パス・ブランチ・worktree 隔離・実行中の件数）。
struct AgentStartProjectHeader: View {
    let name: String
    let path: String
    let branch: String?
    let isolates: Bool
    let runningCount: Int

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            HStack(spacing: 6) {
                Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                if let branch {
                    Text(verbatim: "·")
                    Text(verbatim: branch)
                        .font(.system(size: 12, design: .monospaced))
                }
                Text(verbatim: "·")
                Text(isolates ? "worktree 隔離: オン" : "worktree 隔離: オフ")
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(DSColor.fillSelected, in: RoundedRectangle(cornerRadius: 4))
                if runningCount > 0 {
                    Text(verbatim: "·")
                    Text(String(format: AppLocalizedString.string("実行中 %lld 件", locale: locale), runningCount))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(1)
        }
    }
}

/// 白箱テスト用: レイアウト判定を ImageRenderer 描画時に報告する（表示に影響なし）。
private struct LayoutDecisionReporter: View {
    let stacksVertically: Bool
    var onLayoutDecision: ((Bool) -> Void)?

    var body: some View {
        if let onLayoutDecision {
            let _ = onLayoutDecision(stacksVertically)
        }
        Color.clear.frame(width: 0, height: 0)
    }
}

private struct AgentStartCardButton: View {
    let entry: AgentStartEntry
    let number: Int
    let isDisabled: Bool
    let isCreating: Bool
    let isKeyboardSelected: Bool
    let onSelect: (AgentStartCardMode) -> Void

    @Environment(\.locale) private var locale

    private var descriptor: AgentDescriptor { entry.descriptor }

    private var modes: [AgentStartCardMode] {
        AgentStartCardsModel.modes(for: descriptor)
    }

    private var detailLine: String {
        guard let path = entry.binaryPath else {
            return String(format: AppLocalizedString.string("%@ · 見つかりません", locale: locale), descriptor.binaryName)
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack(alignment: .top, spacing: 10) {
                AgentBrandIcon(descriptor: descriptor, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: descriptor.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(verbatim: detailLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(number)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: DSRadius.s).strokeBorder(DSColor.border, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }

            if entry.isDetected {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 3) {
                    settingRow("モデル", entry.model)
                    settingRow("権限", entry.permission)
                }
                Spacer(minLength: 0)
                if isCreating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("起動しています…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(height: 28)
                } else {
                    HStack(spacing: 6) {
                        ForEach(modes, id: \.self) { mode in
                            modeButton(mode)
                        }
                    }
                }
            } else {
                Text(String(format: AppLocalizedString.string("%@ が PATH に見つかりません。インストールしてアプリを開き直すと、ここから起動できます。", locale: locale), descriptor.binaryName))
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        // 外形の最小幅は AgentStartCardsLayoutPolicy.cardMinOuterWidth（148 + 左右 DSSpacing.m）と揃える。
        .frame(minWidth: 148, maxWidth: .infinity, minHeight: 142, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 14, leading: DSSpacing.m, bottom: 12, trailing: DSSpacing.m))
        .background(entry.isDetected ? DSColor.cardBackground : DSColor.fillSelected, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isKeyboardSelected ? DSColor.accent : DSColor.separator, lineWidth: isKeyboardSelected ? 2 : 1)
        }
        .opacity(isDisabled && !isCreating ? 0.45 : (entry.isDetected ? 1 : 0.85))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: entry.isDetected
            ? descriptor.displayName
            : descriptor.displayName + AppLocalizedString.string("、未検出", locale: locale)))
    }

    private func settingRow(_ label: LocalizedStringKey, _ value: String?) -> some View {
        // GridRow 自体に修飾子を付けると 1 セル扱いになるので、各セルに付ける。
        GridRow {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
            Group {
                if let value {
                    Text(verbatim: value).foregroundStyle(DSColor.textPrimary)
                } else {
                    Text("（CLI の既定）").foregroundStyle(DSColor.textSecondary)
                }
            }
            .font(.system(size: 12))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 構造化チャットに対応すればチャットが主ボタン。対応しなければターミナルが主ボタン（08 S3）。
    private func modeButton(_ mode: AgentStartCardMode) -> some View {
        let isPrimary = mode == .chat || !modes.contains(.chat)
        return Button {
            onSelect(mode)
        } label: {
            Text(LocalizedStringKey(mode.label))
                .font(.system(size: 12.5, weight: isPrimary ? .semibold : .regular))
                .foregroundStyle(isPrimary ? Color.white : DSColor.textPrimary)
                .padding(.horizontal, isPrimary ? 14 : 12)
                .frame(height: 28)
                .background(isPrimary ? DSColor.accentFill : DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if !isPrimary {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.border, lineWidth: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
