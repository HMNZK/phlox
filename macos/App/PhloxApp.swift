import AgentDomain
import AppBootstrap
import AppKit
import Combine
import Darwin
import Sparkle
import SwiftUI
import DashboardFeature
import DesignSystem
import PTYKit
import TerminalUI
import UserNotifications
import SessionFeature

/// 選択中セッションを閉じる。Cmd+W 横取り（AppDelegate）とメニュー（SessionCommands）の
/// 共通処理。閉じられたら true を返す。
@MainActor
@discardableResult
private func performCloseSelectedSession(dashboard: DashboardViewModel?, router: AppRouter?) -> Bool {
    guard let dashboard, let router, let id = router.selectedSession else { return false }
    router.selectedSession = nil
    Task { @MainActor in
        _ = await dashboard.removeSession(id)
    }
    return true
}

/// 初期化失敗の種別。case 名の文字列マッチではなく型で判定する
/// （リネームで案内 UI が静かに壊れるのを防ぐ）。
enum InitFailure {
    case claudeNotFound
    case other(message: String)
}

@main
struct PhloxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var composition: CompositionRoot?
    @State private var initFailure: InitFailure?
    @State private var initializing = false
    /// ドロワーを閉じても実シェルを維持する唯一の所有者。
    @State private var terminalPanelSession: TerminalPanelSession?

    @AppStorage(LanguageSettings.languageKey) private var appLanguageRaw = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    init() {
        UserDefaults.standard.register(defaults: BypassSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: NotificationSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: UsageSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: ThemeStore.defaultsDictionary)
        UserDefaults.standard.register(defaults: TerminalFontSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: LanguageSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: CodexUserHooksSettings.defaultsDictionary)
        UserDefaults.standard.register(defaults: AppIconStore.defaultsDictionary)
        // 選択中カラースキーマのターミナルパレットを、セッション生成より前に反映する。
        TerminalCoordinator.activePalette = DashboardViewModel.makeTerminalPalette(from: ThemeStore.active)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let composition {
                    DashboardView(
                        viewModel: composition.dashboard,
                        router: composition.router,
                        usageMonitor: composition.usage,
                        agentConsoleWindowID: AgentConsoleCommands.windowID,
                        terminalPanel: terminalPanelSession
                    )
                } else if let initFailure {
                    InitErrorView(failure: initFailure, retry: { Task { await initialize() } })
                } else {
                    InitLoadingView()
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .preferredColorScheme(ThemeStore.active.preferredColorScheme)
            .environment(\.locale, appLanguage.locale)
            .task {
                guard composition == nil, !initializing else { return }
                await initialize()
            }
            .onChange(of: composition != nil) { _, hasComposition in
                guard hasComposition, let composition else {
                    appDelegate.ptyManager = nil
                    appDelegate.dashboard = nil
                    appDelegate.router = nil
                    return
                }
                if terminalPanelSession == nil {
                    terminalPanelSession = makeTerminalPanelSession(environment: composition.environment)
                }
                appDelegate.userTerminalController = terminalPanelSession?.controller
                appDelegate.ptyManager = composition.environment.pty as? PTYManager
                appDelegate.dashboard = composition.dashboard
                appDelegate.router = composition.router
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            UpdateCommands(appUpdater: appDelegate.appUpdater)
            ViewCommands(router: composition?.router)
            FontSizeCommands(dashboard: composition?.dashboard)
            SessionCommands(
                dashboard: composition?.dashboard,
                router: composition?.router
            )
            AgentConsoleCommands()
            TerminalPanelCommands(router: composition?.router)
            EditorPanelCommands(router: composition?.router)
        }

        Settings {
            SettingsView(
                appUpdater: appDelegate.appUpdater,
                agentCatalog: composition?.environment.agentCatalog ?? .builtins,
                hookDispatcherPath: composition?.environment.hookDispatcherPath,
                mobileToken: composition?.mobileTokenViewModel
            )
            .environment(\.locale, appLanguage.locale)
        }

        // 対話 TUI 専用のスラッシュコマンド（/plugin・/permissions 等）と、
        // 設定ファイルの手編集でしか触れない項目の置き換え画面。
        // ヘッドレスのセッションへは送れないため、Phlox 側の画面として持つ。
        Window("エージェント管理", id: AgentConsoleCommands.windowID) {
            AgentConsoleWindowView(
                claudeExecutablePath: composition?.environment.claudeBinaryPath,
                pathEnvironment: composition?.environment.pathEnvironment
                    ?? ProcessInfo.processInfo.environment["PATH"] ?? "",
                projectDirectory: selectedProjectDirectory
            )
            .preferredColorScheme(ThemeStore.active.preferredColorScheme)
            .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 900, height: 620)

    }

    /// 選択中セッションが属するプロジェクトのディレクトリ。管理画面の「メモリ」で
    /// プロジェクト側の CLAUDE.md を出すために使う。未選択なら nil。
    @MainActor
    private var selectedProjectDirectory: URL? {
        guard let composition,
              let sessionID = composition.router.selectedSession,
              let session = composition.dashboard.sessions.first(where: { $0.id == sessionID }),
              let projectID = session.projectID,
              let project = composition.dashboard.projects.first(where: { $0.id == projectID })
        else { return nil }
        return project.directoryURL
    }

    @MainActor
    private func makeTerminalPanelSession(environment: AppEnvironment) -> TerminalPanelSession {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return TerminalPanelSession(
            controller: UserTerminalController(
                pty: environment.pty,
                shellPath: loginShellPath(),
                workingDirectory: home,
                environment: [
                    "HOME": home,
                    "PATH": environment.pathEnvironment,
                    "TERM": "xterm-256color",
                ]
            )
        )
    }

    /// GUI 起動では `SHELL` が注入されないことがあるため、ログイン設定の shell を使う。
    private func loginShellPath() -> String {
        guard let shell = getpwuid(getuid())?.pointee.pw_shell else {
            return "/bin/zsh"
        }
        let path = String(cString: shell)
        return path.isEmpty ? "/bin/zsh" : path
    }

    private func initialize() async {
        initializing = true
        initFailure = nil
        do {
            let root = try await CompositionRoot { dashboard, pty in
                // 復元完了前の SIGTERM でも子終了経路が使えるよう、start() より前に配線する。
                appDelegate.ptyManager = pty
                appDelegate.dashboard = dashboard
            }
            composition = root
            appDelegate.ptyManager = root.environment.pty as? PTYManager
            appDelegate.dashboard = root.dashboard
            appDelegate.router = root.router
        } catch {
            if case CompositionRoot.CompositionError.claudeNotFound = error {
                initFailure = .claudeNotFound
            } else {
                initFailure = .other(message: String(describing: error))
            }
            appDelegate.ptyManager = nil
            appDelegate.dashboard = nil
            appDelegate.router = nil
        }
        initializing = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let appUpdater = AppUpdater()
    var ptyManager: PTYManager? {
        didSet {
            // シグナルハンドラ（バックグラウンドキュー）が MainActor を経由せずに PTYManager へ
            // 到達できるよう、nonisolated なロック付きの箱を同期更新する。これがないと、アプリが
            // ハングして MainActor がブロック中に SIGTERM/SIGINT が来たとき、ハンドラ内の
            // MainActor ホップが永久に進まず子終了に到達できない（デッドロック窓）。
            ptyManagerBox.set(ptyManager)
        }
    }
    var dashboard: DashboardViewModel? {
        didSet {
            if let oldDashboard = oldValue {
                if let newDashboard = dashboard {
                    if oldDashboard !== newDashboard {
                        oldDashboard.unseenCompletionCountDidChange = nil
                        DashboardSessionSpawnHooks.clearHandlers(on: oldDashboard)
                    }
                } else {
                    oldDashboard.unseenCompletionCountDidChange = nil
                    DashboardSessionSpawnHooks.clearHandlers(on: oldDashboard)
                }
            }
            dashboard?.unseenCompletionCountDidChange = { [weak self] count in
                self?.updateDockBadge(count: count)
            }
            updateDockBadge(count: dashboard?.unseenCompletionCount ?? 0)
        }
    }
    var router: AppRouter?
    /// ドロワーを閉じても保持されるユーザー用シェル。終了経路だけが明示的に停止する。
    var userTerminalController: UserTerminalController?
    private var closeSessionMonitor: Any?

    /// 子セッションの一括終了を「高々 1 回」だけ起動するためのガード。
    /// シグナル終了経路（SIGTERM/SIGINT）と GUI 正常終了経路（applicationShouldTerminate）が
    /// 競合・二重発火しても、実際の終了処理は 1 回だけにする。
    let cleanupGuard = CleanupGuard()

    /// シグナルハンドラから MainActor を経由せずに PTYManager を読むための nonisolated な箱。
    /// `ptyManager` の didSet で同期する。PTYManager は actor（Sendable）なので参照を安全に保持できる。
    nonisolated fileprivate let ptyManagerBox = SignalSafeBox<PTYManager?>(nil)

    /// SIGTERM / SIGINT を監視する DispatchSource。AppDelegate が保持して生存させる
    /// （ローカル変数のままだと即座に cancel され、ハンドラが発火しない）。
    private var signalSources: [DispatchSourceSignal] = []

    /// 子終了処理のタイムアウト。applicationShouldTerminate と揃える。
    static let cleanupTimeout: Duration = .seconds(5)
    /// チャット transcript flush の上限。書き込み完了を待つが、終了不能ハングは作らない。
    static let transcriptFlushTimeout: Duration = .seconds(3)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        SessionCompletionNotifier.requestAuthorization()

        // 選択中アプリアイコンを Dock（実行中アプリのアイコン）へ再適用する。macOS には iOS の
        // setAlternateIconName が無いため、NSApp.applicationIconImage をランタイム適用する。
        applyAppIcon()

        installSignalHandlers()

        // SwiftUI exposes CommandGroupPlacement.newItem but no public Close-specific placement
        // in the local SDK interface. Intercept Cmd+W before AppKit's standard Close command so
        // the shortcut deterministically closes the selected session instead of the window.
        closeSessionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.isCommandW else { return event }
            guard let self, self.closeSelectedSession() else { return event }
            return nil
        }
    }

    /// 保存済みの選択アイコンを Dock（実行中アプリのアイコン）へ適用する。選択値の解決は
    /// `AppIconStore`（DesignSystem・テスト済み）に委ね、ここは画像解決と適用だけを行う。
    func applyAppIcon() {
        let option = AppIconStore.selected(in: .standard)
        if let image = NSImage(named: option.assetName) {
            NSApp.applicationIconImage = image
        }
    }

    /// 全チャットセッションの transcript を書き切り、タイムアウトで打ち切る。
    ///
    /// 各セッションの `flushTranscriptNow()` は子タスクで同時起動する（直列 await だと
    /// 先頭セッションの store stall で後続が enqueue すらされず契約違反になる）。
    /// 全体完了を `TerminationFlushRace` で timeout と競わせる。timeout 勝利後は flush
    /// 側を await しない（`withTaskGroup` の暗黙 await で reply がハングするのを避ける）。
    @MainActor
    static func flushChatTranscriptsForTermination(
        dashboard: DashboardViewModel?,
        timeout: Duration
    ) async {
        guard let dashboard else { return }
        let sessions = dashboard.sessionNodes.compactMap(\.appServer)
        guard !sessions.isEmpty else { return }

        await TerminationFlushRace.raceAllParallel(
            timeout: timeout,
            bodies: sessions.map { session in
                { await session.flushTranscriptNow() }
            }
        )
        // timeout 勝利時も各 flush 子タスクは走らせたまま（プロセス終了で回収）。reply はここで返る。
    }

    /// SIGTERM（`kill <pid>`）/ SIGINT（Ctrl-C）受信時に、子セッションを一括終了してから
    /// プロセスを終了させる。これがないと、これらのシグナルでデーモンが落ちたとき spawn 済みの
    /// 全セッションが孤児化して生き残る。
    ///
    /// 設計上の要点:
    /// - DispatchSource を設置する前に該当シグナルの既定動作を無効化（SIG_IGN）する。無効化しないと
    ///   デフォルト動作（プロセス即死）が先に走り、ハンドラが発火しない。
    /// - ハンドラは `ptyManagerBox`（nonisolated なロック付きの箱）から PTYManager を直接読み、
    ///   MainActor を一切経由しない。これにより、アプリがハングして MainActor（メインスレッド）が
    ///   ブロック中に SIGTERM/SIGINT が来ても、グレースフルな子終了が走る。
    ///   （MainActor ホップに依存すると、ブロック中はそのホップが永久に進まずデッドロックする。）
    /// - ハンドラは actor の `terminateAllAndWait` の完了を `DispatchSemaphore` で待ってから `exit` する。
    ///   待たずに exit すると子終了が中断され無意味になる。`terminateAllAndWait` は PTYManager
    ///   （独立 actor）上で走り、バックグラウンドキューのスレッドをセマフォでブロックしても
    ///   MainActor を経由しないため、MainActor のブロック状態に左右されない。
    /// - idempotency は `cleanupGuard` で担保し、正常終了経路（applicationShouldTerminate）と競合しない。
    /// - SIGKILL（kill -9）やハードクラッシュはプロセス内で捕捉不可能であり、ここでは扱えない。
    ///   その取りこぼしは task-3 の「起動時 reap」で回収する。
    private func installSignalHandlers() {
        let queue = DispatchQueue(label: "com.phlox.signal-cleanup")
        signalSources = TerminationSignalHandlers.install(
            signals: [SIGTERM, SIGINT],
            queue: queue,
            handler: { @Sendable [cleanupGuard, ptyManagerBox] in
                AppDelegate.handleTerminationSignal(
                    cleanupGuard: cleanupGuard,
                    ptyManagerBox: ptyManagerBox
                )
            }
        )
    }

    /// シグナル受信時の終了処理本体。バックグラウンドキューで実行される。
    nonisolated private static func handleTerminationSignal(
        cleanupGuard: CleanupGuard,
        ptyManagerBox: SignalSafeBox<PTYManager?>
    ) {
        // 起動権を取れなければ（正常終了経路が先行している等）、子終了を二重に走らせない。
        guard cleanupGuard.beginCleanup() else { return }

        // MainActor を経由せず、nonisolated な箱から直接 PTYManager を読む。
        // MainActor がブロック中でも到達できる。
        let manager = ptyManagerBox.value

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if let manager {
                await manager.terminateAllAndWait(timeout: Self.cleanupTimeout)
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let closeSessionMonitor {
            NSEvent.removeMonitor(closeSessionMonitor)
        }
        closeSessionMonitor = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func closeSelectedSession() -> Bool {
        performCloseSelectedSession(dashboard: dashboard, router: router)
    }

    private func updateDockBadge(count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheckForUpdates = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = canCheckForUpdates
            }
        }
    }

    /// 起動時の自動アップデート確認の有効/無効。Sparkle の updater にプロキシする。
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// 「エージェント管理」ウィンドウを開くメニュー項目。
struct AgentConsoleCommands: Commands {
    static let windowID = "agent-console"

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("エージェント管理…") {
                openWindow(id: Self.windowID)
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
        }
    }
}

private struct TerminalPanelCommands: Commands {
    var router: AppRouter?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("ターミナル") {
                router?.toggleTerminalPanel()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(router == nil)
        }
    }
}

private struct EditorPanelCommands: Commands {
    var router: AppRouter?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("エディタ") {
                router?.toggleEditorPanel()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(router == nil)
        }
    }
}

private struct UpdateCommands: Commands {
    @ObservedObject var appUpdater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("アップデートを確認…") {
                appUpdater.checkForUpdates()
            }
            .disabled(!appUpdater.canCheckForUpdates)
        }
    }
}

private struct ViewCommands: Commands {
    var router: AppRouter?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("サイドバーを表示／隠す") {
                router?.toggleSidebar()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(router == nil)

            Button("インスペクターを表示／隠す") {
                router?.toggleInspector()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(router == nil)

            Button("表示モードを切り替え") {
                router?.toggleViewMode()
            }
            .keyboardShortcut("g", modifiers: [.command, .control])
            .disabled(router == nil)
        }
    }
}

private struct FontSizeCommands: Commands {
    var dashboard: DashboardViewModel?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("文字を大きく") {
                dashboard?.adjustTerminalFontSize(by: TerminalFontSettings.step)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(dashboard == nil)

            Button("文字を小さく") {
                dashboard?.adjustTerminalFontSize(by: -TerminalFontSettings.step)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(dashboard == nil)
        }
    }
}

private struct SessionCommands: Commands {
    var dashboard: DashboardViewModel?
    var router: AppRouter?

    var body: some Commands {
        CommandMenu("セッション") {
            ForEach(AgentKind.allCases) { kind in
                Button { spawnSession(kind: kind) } label: {
                    Label(kind.displayName, systemImage: kind.symbolName)
                }
                .keyboardShortcut(Self.shortcuts[kind])
                .disabled(!canSpawn(kind: kind))
            }

            Divider()

            Button("次のセッション") { selectAdjacentSession(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(dashboard == nil)
            Button("前のセッション") { selectAdjacentSession(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(dashboard == nil)

            Button {
                closeSelectedSession()
            } label: {
                Label("セッションを閉じる", systemImage: "xmark.circle")
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!canCloseSession)

            Divider()

            // 対話 TUI の /export 相当。チャットセッションのみ対象（PTY は transcript を持たない）。
            Button {
                guard let chat = exportableChatSession else { return }
                ChatTranscriptExportAction.save(session: chat)
            } label: {
                Label("会話を書き出す…", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportableChatSession == nil)

            Button {
                guard let chat = exportableChatSession else { return }
                ChatTranscriptExportAction.copyToPasteboard(session: chat)
            } label: {
                Label("会話を Markdown でコピー", systemImage: "doc.on.doc")
            }
            .disabled(exportableChatSession == nil)
        }
    }

    private var exportableChatSession: ChatSessionViewModel? {
        ChatTranscriptExportAction.selectedChatSession(dashboard: dashboard, router: router)
    }

    private static let shortcuts: [AgentKind: KeyboardShortcut] = [
        .claudeCode: KeyboardShortcut("n", modifiers: .command),
        .codex: KeyboardShortcut("n", modifiers: [.command, .shift]),
        .cursor: KeyboardShortcut("n", modifiers: [.command, .option]),
    ]

    private var canCloseSession: Bool {
        router?.selectedSession != nil
    }

    private func canSpawn(kind: AgentKind) -> Bool {
        guard let dashboard else { return false }
        guard !dashboard.projects.isEmpty else { return false }
        return dashboard.availableAgentKinds.contains(kind)
    }

    private func spawnSession(kind: AgentKind) {
        guard let dashboard, let router else { return }
        Task { @MainActor in
            if let newID = try? await dashboard.spawnNewSessionUsingDefaultProject(
                kind: kind,
                selectedSessionID: router.selectedSession
            ) {
                router.selectedSession = newID
            }
        }
    }

    private func closeSelectedSession() {
        performCloseSelectedSession(dashboard: dashboard, router: router)
    }

    private func selectAdjacentSession(forward: Bool) {
        guard let dashboard, let router else { return }
        if let nextID = dashboard.adjacentSessionID(from: router.selectedSession, forward: forward) {
            router.selectedSession = nextID
        }
    }
}

private extension NSEvent {
    var isCommandW: Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && charactersIgnoringModifiers?.lowercased() == "w"
    }
}

private struct InitLoadingView: View {
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            ProgressView()
                .controlSize(.large)
            Text("起動中…")
                .font(DSFont.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InitErrorView: View {
    let failure: InitFailure
    let retry: () -> Void

    private var isClaudeNotFound: Bool {
        if case .claudeNotFound = failure { return true }
        return false
    }

    private var detailMessage: String {
        if case .other(let message) = failure { return message }
        return ""
    }

    var body: some View {
        VStack(spacing: DSSpacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(DSColor.statusError)

            Text("初期化に失敗しました")
                .font(DSFont.heroTitle)

            if isClaudeNotFound {
                VStack(spacing: DSSpacing.s) {
                    Text("Claude Code CLI が見つかりませんでした。")
                    Text("次のコマンドでインストールしてください:")
                        .foregroundStyle(.secondary)
                    Text("npm install -g @anthropic-ai/claude-code")
                        .font(DSFont.monoCaption)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.vertical, DSSpacing.s)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                .multilineTextAlignment(.center)
            } else {
                Text(detailMessage)
                    .font(DSFont.monoCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, DSSpacing.xl)
            }

            Button(action: retry) {
                Label("再試行", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(DSSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
