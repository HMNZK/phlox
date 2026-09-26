import SwiftUI
import AppKit
import UserNotifications
import AgentDomain
import DesignSystem
import SessionFeature

// MARK: - S1 初回起動

/// プロジェクトが 1 件もないときの案内（08 S1）。初回は検出結果と通知まで、2 回目以降は手順 1 だけ。
struct StartOnboardingView: View {
    let entries: [AgentStartEntry]
    let showsAllSteps: Bool
    let onAddFolder: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if showsAllSteps {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phlox へようこそ")
                            .font(DSFont.emptyTitle)
                            .tracking(-0.3)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("複数のコーディングエージェントを 1 つのウィンドウで動かし、承認と質問にまとめて答えます。始めるには作業フォルダを 1 つ追加してください。")
                            .font(.system(size: 13.5))
                            .lineSpacing(6)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                step(1, title: "プロジェクトを追加") {
                    Text("エージェントはこのフォルダの中で作業します。フォルダ自体を Phlox が移動・削除することはありません。")
                        .font(DSFont.dense)
                        .lineSpacing(4)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onAddFolder) {
                        HStack(spacing: 8) {
                            Text("フォルダを追加…")
                            Text(verbatim: "⌘O").font(DSFont.meta).opacity(0.85)
                        }
                        .font(DSFont.row.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if showsAllSteps {
                    step(2, title: "使えるエージェント", note: "PATH から自動で検出") {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                detectionRow(entry)
                                    .overlay(alignment: .top) {
                                        if index > 0 { Rectangle().fill(DSColor.separator).frame(height: 1) }
                                    }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DSColor.separator, lineWidth: 1))
                        Text("ほかの CLI は ~/.config/phlox/agents.json に書くと追加できます。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    step(3, title: "通知（任意）") {
                        HStack(spacing: 10) {
                            Text("承認待ちや完了を、ほかのアプリを使っている間も知らせます。")
                                .font(DSFont.dense)
                                .lineSpacing(4)
                                .foregroundStyle(DSColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            notificationControl
                        }
                    }
                    Text("この画面の内容は、あとから 設定（⌘,）でも変更できます。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(EdgeInsets(top: 64, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: showsAllSteps) {
            guard showsAllSteps else { return }
            await refreshNotificationStatus()
        }
    }

    private func step<Content: View>(
        _ number: Int,
        title: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // 08 S1: 番号の丸は 20pt（手順 1 だけ accent）。本文は丸の幅＋間隔の 30pt だけ字下げする。
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(DSFont.meta.weight(.bold))
                    .foregroundStyle(number == 1 ? Color.white : DSColor.textPrimary)
                    .frame(width: 20, height: 20)
                    .background(number == 1 ? DSColor.accentFill : DSColor.segmentTrack, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(DSFont.sessionTitle)
                    .foregroundStyle(DSColor.textPrimary)
                if let note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 30)
        }
    }

    private func detectionRow(_ entry: AgentStartEntry) -> some View {
        HStack(spacing: 10) {
            AgentInitialTile(descriptor: entry.descriptor, size: 22, fontScale: 0.42)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.descriptor.displayName)
                    .font(DSFont.row.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                Text(verbatim: entry.binaryPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
                    ?? String(format: AppLocalizedString.string("%@ · 見つかりません", locale: locale), entry.descriptor.binaryName))
                    .font(DSFont.monoCaption)
                    .foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Text(entry.isDetected ? "検出済み" : "未検出")
                .font(DSFont.stateLabel)
                .foregroundStyle(entry.isDetected ? DSColor.diffAdded : DSColor.attentionInk(.approval))
            if !entry.isDetected, let url = AgentInstallGuide.url(for: entry.descriptor.ref) {
                Button("入手方法 ↗") { openURL(url) }
                    .buttonStyle(.plain)
                    .font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.accentInk)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notificationControl: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Text("許可済み")
                .font(DSFont.dense.weight(.medium))
                .foregroundStyle(DSColor.textSecondary)
        case .denied:
            softButton("システム設定を開く…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            softButton("通知を許可…") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private func softButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.dense)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.border, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshNotificationStatus() async {
        // テストのホスト（バンドル外）では通知センターを使えない。
        guard Bundle.main.bundleIdentifier != nil else { return }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - 新規セッションの表（⌘N・サイドバーの ＋）

/// 種別 × 開き方の表（Sidebar F5 / 08 の全入口）。行は `NewSessionMenuModel` から組む。
struct NewSessionTable: View {
    let projects: [Project]
    let model: NewSessionMenuModel
    let defaultBackend: DefaultSessionBackendPreference
    /// 実行ファイルが見つかった種別（`AgentRef.id`）。ほかは選べない状態で出す（08 ②）。
    let detectedRefIDs: Set<String>
    /// 起動中は選べない（08 ①: 起動中は全入口を無効にする）。
    let isCreating: Bool
    let onStart: (AgentRef, ProjectID, SessionBackend) -> Void

    @State private var projectID: ProjectID?
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        projects: [Project],
        projectID: ProjectID?,
        model: NewSessionMenuModel,
        defaultBackend: DefaultSessionBackendPreference,
        detectedRefIDs: Set<String>,
        isCreating: Bool,
        onStart: @escaping (AgentRef, ProjectID, SessionBackend) -> Void
    ) {
        self.projects = projects
        self.model = model
        self.defaultBackend = defaultBackend
        self.detectedRefIDs = detectedRefIDs
        self.isCreating = isCreating
        self.onStart = onStart
        _projectID = State(initialValue: projectID)
    }

    private var rows: [NewSessionTableRow] { NewSessionTableRow.rows(from: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.element.ref.id) { index, row in
                    rowView(row, index: index)
                }
            }
            .padding(6)
            Divider()
            footer
        }
        .frame(minWidth: 352)
        .fixedSize()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let number = Int(press.characters), number >= 1, number <= rows.count else { return .ignored }
            selectedIndex = number - 1
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            guard !rows.isEmpty else { return .ignored }
            let step = press.key == .upArrow ? -1 : 1
            selectedIndex = (selectedIndex + step + rows.count) % rows.count
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard rows.indices.contains(selectedIndex) else { return .ignored }
            let row = rows[selectedIndex]
            let mode = NewSessionKeys.mode(default: defaultBackend, option: press.modifiers.contains(.option), supportsChat: row.supportsChat)
            start(row, backend: mode.backend)
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("新規セッション")
                .font(DSFont.row.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: 0)
            Menu {
                ForEach(projects) { project in
                    Button(project.name) { projectID = project.id }
                }
            } label: {
                if let name = projects.first(where: { $0.id == projectID })?.name {
                    Text(verbatim: name)
                } else {
                    Text("プロジェクトを選択")
                }
            }
            .font(DSFont.auxiliary)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(Text("作成先のプロジェクト"))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func rowView(_ row: NewSessionTableRow, index: Int) -> some View {
        let isSelected = index == selectedIndex
        return HStack(spacing: 0) {
            Text(verbatim: "\(index + 1)")
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.textTertiary)
                .frame(width: 20, alignment: .leading)
                .accessibilityHidden(true)
            Text(verbatim: row.title)
                .font(DSFont.row)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if detectedRefIDs.contains(row.ref.id) {
                Group {
                    if row.supportsChat {
                        cellButton("チャット", primary: true) { start(row, backend: .appServer) }
                    } else {
                        Text("非対応")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                }
                .frame(width: 76)
                cellButton("ターミナル", primary: !row.supportsChat) { start(row, backend: .pty) }
                    .frame(width: 100)
            } else {
                Text("未検出")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(width: 176)
            }
        }
        .opacity(detectedRefIDs.contains(row.ref.id) ? 1 : 0.6)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(isSelected ? DSColor.fillSelected : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isSelected && focused {
                RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = index }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: detectedRefIDs.contains(row.ref.id)
            ? row.title
            : row.title + AppLocalizedString.string("、未検出", locale: locale)))
    }

    private func cellButton(_ title: LocalizedStringKey, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.auxiliary.weight(primary ? .semibold : .regular))
                .foregroundStyle(primary ? Color.white : DSColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(primary ? DSColor.accentFill : DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if !primary { RoundedRectangle(cornerRadius: 5).strokeBorder(DSColor.border, lineWidth: 0.5) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCreating || projectID == nil)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(String(format: AppLocalizedString.string("1–%lld で種別", locale: locale), rows.count))
            Text(verbatim: NewSessionKeys.hint(default: defaultBackend, locale: locale))
            Spacer(minLength: 0)
            Text(defaultBackend == .chat ? "既定の開き方: チャット" : "既定の開き方: ターミナル")
        }
        .font(.system(size: 10.5))
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(DSColor.textTertiary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    @Environment(\.locale) private var locale

    private func start(_ row: NewSessionTableRow, backend: SessionBackend) {
        // 作成先が決まるまでは起動しない（未選択なら見出しで選ぶ）。
        guard let projectID, !isCreating, detectedRefIDs.contains(row.ref.id) else { return }
        dismiss()
        onStart(row.ref, projectID, backend)
    }
}

/// 表の 1 行（種別）。ビューの外に置き、メインスレッド外のテストからも組み立てられるようにする。
struct NewSessionTableRow: Equatable {
    let title: String
    let ref: AgentRef
    let supportsChat: Bool

    /// ターミナルの列は全種別にあるので、その並びを行にする。チャットは対応する種別だけ。
    static func rows(from model: NewSessionMenuModel) -> [NewSessionTableRow] {
        let items = model.sections.flatMap(\.items)
        let chatRefs = Set(items.filter { $0.backend == .appServer }.map(\.ref.id))
        return items.filter { $0.backend == .pty }.map {
            NewSessionTableRow(title: $0.title, ref: $0.ref, supportsChat: chatRefs.contains($0.ref.id))
        }
    }
}

/// 押すと新規セッションの表を出すボタン（サイドバーの ＋・下端・グリッドの空状態）。
struct NewSessionPopoverButton<Table: View, Label: View>: View {
    let table: () -> Table
    let label: () -> Label
    /// 開閉状態を親が持つとき（ホバー中だけ出るボタンは、ボタンが消えるとポップアップも閉じるため）。
    let externalPresented: Binding<Bool>?

    @State private var ownPresented = false
    @Environment(\.locale) private var locale

    init(
        isPresented: Binding<Bool>? = nil,
        @ViewBuilder table: @escaping () -> Table,
        @ViewBuilder label: @escaping () -> Label
    ) {
        externalPresented = isPresented
        self.table = table
        self.label = label
    }

    private var presented: Binding<Bool> { externalPresented ?? $ownPresented }

    var body: some View {
        Button { presented.wrappedValue.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: presented, arrowEdge: .bottom) {
                table().environment(\.locale, locale)
            }
    }
}

/// ↩ は既定の開き方、⌥↩ はもう一方（ADR 0071: GUI からの作成は既定の開き方に従う）。
enum NewSessionKeys {
    static func mode(default preference: DefaultSessionBackendPreference, option: Bool, supportsChat: Bool) -> AgentStartCardMode {
        guard supportsChat else { return .terminal }
        let primary: AgentStartCardMode = preference == .chat ? .chat : .terminal
        guard option else { return primary }
        return primary == .chat ? .terminal : .chat
    }

    static func hint(default preference: DefaultSessionBackendPreference, locale: Locale) -> String {
        AppLocalizedString.string(preference == .chat ? "↩ チャット · ⌥↩ ターミナル" : "↩ ターミナル · ⌥↩ チャット", locale: locale)
    }
}

// MARK: - 起動前の確認（F1・F4）

/// 新規セッションの起動要求。確認のあとに同じ内容で起動し直すために持つ。
struct NewSessionRequest: Equatable {
    let ref: AgentRef
    let projectID: ProjectID
    let backend: SessionBackend
}

/// 起動前・起動失敗時に出す確認（08 F1・F4）。
enum SpawnGuard: Identifiable {
    /// 隔離オフのプロジェクトで、同じ作業ディレクトリにセッションが動いている。
    case collision(NewSessionRequest, directory: String, peers: [SessionID])
    /// worktree を作れず起動を中止した。
    /// `existingWorktree` は 09 E4「既存の worktree を使う」で使える、このリポジトリの worktree の場所（無ければ nil）。
    case worktreeFailed(NewSessionRequest, agentName: String, log: String, existingWorktree: String?)

    var id: String {
        switch self {
        case .collision: "collision"
        case .worktreeFailed: "worktreeFailed"
        }
    }
}

enum NewSessionCollisionGate {
    /// 隔離オフのとき、プロジェクトのフォルダで動いているセッション（08 F1）。隔離オンなら空。
    static func peers(project: Project, among workspaces: [SessionWorkspace]) -> [SessionID] {
        guard !project.usesWorktreeIsolation else { return [] }
        let directory = WorkspaceCollisionPolicy.canonicalPath(project.directoryPath)
        return workspaces
            .filter { $0.isActive && WorkspaceCollisionPolicy.canonicalPath($0.workingDirectory) == directory }
            .map(\.sessionID)
    }

    /// worktree の失敗として確認に出す内容。git の出力があればそれを、無ければ理由の文を出す。
    static func worktreeFailureLog(_ error: Error) -> String? {
        guard let error = error as? WorktreeIsolationSpawnError else { return nil }
        if case .worktreeCreationFailed(_, _, let detail) = error, !detail.isEmpty {
            return detail
        }
        return error.localizedDescription
    }

    /// git の出力が「そのブランチは既存の worktree で使われている」と言っていれば、その worktree の場所（09 E4「既存の worktree を使う」）。
    /// 出力から場所を確かめられないとき・その場所がいまこのリポジトリの作業ツリーとして働いていないときは nil（ボタンを出さない）。
    static func existingWorktree(in log: String, repository: URL) async -> String? {
        let pattern = #"(?:already checked out at|already used by worktree at) '([^']+)'"#
        guard let match = log.range(of: pattern, options: .regularExpression) else { return nil }
        let quoted = log[match].split(separator: "'", omittingEmptySubsequences: false)
        guard quoted.count >= 2 else { return nil }
        let path = (String(quoted[quoted.count - 2]) as NSString).expandingTildeInPath
        guard await WorktreeIsolationGit.isWorkingTree(URL(fileURLWithPath: path, isDirectory: true), of: repository) else {
            return nil
        }
        return path
    }
}

struct SpawnGuardSheet: View {
    let spawnGuard: SpawnGuard
    let sessionNode: (SessionID) -> SessionNode?
    let onCancel: () -> Void
    /// 起動する。true = worktree で分ける、false = 分けない。
    let onLaunch: (Bool) -> Void
    /// 既存の worktree（パス）で起動する。
    let onUseWorktree: (String) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        switch spawnGuard {
        case .collision(_, _, let peers):
            // 09 E3: 取り返せる型。ボタンは縦に並べ、既定（↩）の「worktree で分けて起動」を一番下に置く。
            DSDialog(
                .recoverable,
                title: title,
                message: message,
                buttons: [
                    DSDialogButton("キャンセル", action: onCancel),
                    DSDialogButton("同じディレクトリで起動") { onLaunch(false) },
                    DSDialogButton("worktree で分けて起動", role: .primary) { onLaunch(true) },
                ],
                onCancel: onCancel
            ) {
                peerList(peers)
            }
        case .worktreeFailed(_, _, let log, let existingWorktree):
            // 09 E4: お知らせの型。「閉じる」が既定、次の手の「隔離なしで起動」を先に置く。
            DSDialog(
                .notice,
                title: title,
                message: message,
                buttons: [DSDialogButton("隔離なしで起動") { onLaunch(false) }]
                    + (existingWorktree.map { path in
                        [DSDialogButton("既存の worktree を使う") { onUseWorktree(path) }]
                    } ?? [])
                    + [DSDialogButton("閉じる", role: .primary, action: onCancel)],
                onCancel: onCancel
            ) {
                DSDialogLog(log)
            }
        }
    }

    private var title: String {
        switch spawnGuard {
        case .collision(_, let directory, let peers):
            String(format: AppLocalizedString.string("%@ では、すでに %lld 件のセッションが動いています", locale: locale),
                   (directory as NSString).abbreviatingWithTildeInPath, peers.count)
        case .worktreeFailed:
            AppLocalizedString.string("worktree を作成できなかったため、起動を中止しました", locale: locale)
        }
    }

    private var message: String {
        switch spawnGuard {
        case .collision:
            AppLocalizedString.string("同じファイルを書き換えると変更がぶつかることがあります。worktree で分けて起動できます。", locale: locale)
        case .worktreeFailed(_, let agentName, _, _):
            String(format: AppLocalizedString.string("%@ の新しいセッションは起動していません。", locale: locale), agentName)
        }
    }

    /// 08 F1: 衝突相手の一覧。行の高さ 30、状態（52 幅・11pt。対応待ちは太字でその状態の色）、名前、種別の記号。
    private func peerList(_ peers: [SessionID]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(peers.enumerated()), id: \.element) { index, id in
                if let node = sessionNode(id) {
                    let state = node.gridDisplayState
                    HStack(spacing: 10) {
                        Text(verbatim: state.localizedLabel(locale: locale))
                            .font(DSFont.meta.weight(state.attentionKind != nil ? .bold : .medium))
                            .foregroundStyle(state.attentionKind.map { DSColor.attentionInk($0) } ?? DSColor.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        Text(verbatim: node.displayName)
                            .font(DSFont.dense)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: node.agentDescriptor.tabInitials)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(DSColor.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(DSColor.separator).frame(height: 1) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DSColor.separator, lineWidth: 1))
    }
}
