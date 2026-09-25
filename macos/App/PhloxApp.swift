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

/// ⌘W の横取り（AppDelegate）とメニュー（SessionCommands）の共通処理（13 Review で確定）：
/// 子タブはそのタブを閉じ、会話・グリッドは確認してからセッションを削除する。
/// 対象が無ければ false を返し、ウィンドウを閉じる標準動作に任せる。
@MainActor
@discardableResult
private func performCloseSelectedSession(router: AppRouter?) -> Bool {
    router?.requestClose() ?? false
}

/// 初期化失敗の種別。case 名の文字列マッチではなく型で判定する
/// （リネームで案内 UI が静かに壊れるのを防ぐ）。
enum InitFailure {
    case claudeNotFound
    /// 11 I2: 制御用・フック用のサーバーを開始できなかった。
    case serverFailed(message: String)
    /// 11 I3: 以前のバージョンのデータを移行できなかった。
    case migrationFailed(message: String)
    /// 旧アプリ（AgentDashboard）が起動中で移行できなかった。終了してから再試行すれば移行できる。
    case legacyAppRunning(message: String)
    case other(message: String)

    /// 原因の文（そのまま等幅で出す）。
    var log: String {
        switch self {
        case .claudeNotFound: "npm install -g @anthropic-ai/claude-code"
        case .serverFailed(let message), .migrationFailed(let message), .legacyAppRunning(let message), .other(let message): message
        }
    }

    /// 起動の失敗を書き残すファイル（「ログを Finder で表示」で示す）。
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Phlox/startup-error.log")

    /// 失敗の内容を時刻つきで書き残し、書けたかを返す。書けなくても起動エラーの画面は出す。
    @discardableResult
    func writeLog() -> Bool {
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(log)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            return (try? handle.seekToEnd()).flatMap { _ in try? handle.write(contentsOf: Data(line.utf8)) } != nil
        }
        return (try? Data(line.utf8).write(to: url)) != nil
    }
}

@main
struct PhloxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var composition: CompositionRoot?
    @State private var initFailure: InitFailure?
    /// 今回の失敗をログへ書けたか（書けなければ「ログを Finder で表示」を無効にする）。
    @State private var initFailureLogged = false
    @State private var initializing = false
    /// 上段右端の共通ターミナル（ホームで開く）の唯一の所有者。
    @State private var terminalPanelSession: TerminalPanelSession?
    /// セッションごとのターミナルタブ（その worktree で開く）の唯一の所有者。
    @State private var sessionTerminals: SessionTerminalStore?

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
                        commonTerminal: terminalPanelSession,
                        sessionTerminals: sessionTerminals
                    )
                } else if let initFailure {
                    InitErrorView(failure: initFailure, logWritten: initFailureLogged, retry: { Task { await initialize() } })
                } else {
                    InitLoadingView()
                }
            }
            .frame(minWidth: 720, minHeight: 520)
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
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    terminalPanelSession = makeTerminalPanelSession(environment: composition.environment, workingDirectory: home)
                }
                if sessionTerminals == nil {
                    let environment = composition.environment
                    sessionTerminals = SessionTerminalStore { workingDirectory in
                        makeTerminalPanelSession(environment: environment, workingDirectory: workingDirectory)
                    }
                }
                appDelegate.userTerminalController = terminalPanelSession?.controller
                appDelegate.sessionUserTerminals = sessionTerminals
                appDelegate.ptyManager = composition.environment.pty as? PTYManager
                appDelegate.dashboard = composition.dashboard
                appDelegate.router = composition.router
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 01 F: メニューは Phlox / ファイル / 表示 / セッション の 4 つ（「タブ」メニューは置かない）。
            FileCommands(dashboard: composition?.dashboard, router: composition?.router)
            UpdateCommands(appUpdater: appDelegate.appUpdater)
            ViewCommands(dashboard: composition?.dashboard, router: composition?.router)
            SessionCommands(
                dashboard: composition?.dashboard,
                router: composition?.router
            )
            AgentConsoleCommands()
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

    /// 共通ターミナルはホーム、ターミナルタブはそのセッションの worktree で開く。
    @MainActor
    private func makeTerminalPanelSession(environment: AppEnvironment, workingDirectory: String) -> TerminalPanelSession {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return TerminalPanelSession(
            controller: UserTerminalController(
                pty: environment.pty,
                shellPath: loginShellPath(),
                workingDirectory: workingDirectory,
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
        // 再試行の連打で初期化（と移行のロック）が重ならないようにする。
        guard !initializing else { return }
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
            let failure: InitFailure = switch error {
            case CompositionRoot.CompositionError.claudeNotFound: .claudeNotFound
            case CompositionRoot.CompositionError.migrationFailed(let reason)
                where reason == AppSupportMigrator.legacyApplicationRunningReason:
                .legacyAppRunning(message: "AppSupportMigrator: \(reason)")
            case CompositionRoot.CompositionError.migrationFailed(let reason): .migrationFailed(message: "AppSupportMigrator: \(reason)")
            case _ where CompositionRoot.isServerStartFailure(error): .serverFailed(message: String(describing: error))
            default: .other(message: String(describing: error))
            }
            initFailureLogged = failure.writeLog()
            initFailure = failure
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
            observeAttention()
        }
    }
    var router: AppRouter?
    /// 共通ターミナルのシェル。終了経路だけが明示的に停止する。
    var userTerminalController: UserTerminalController?
    /// セッションごとのターミナルタブのシェル。終了経路でまとめて停止する。
    var sessionUserTerminals: SessionTerminalStore?
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 01 F: OS のウィンドウタブ（「タブバーを表示」）は Phlox のタブと紛らわしいので出さない。
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        SessionCompletionNotifier.requestAuthorization()
        SessionCompletionNotifier.context = { [weak self] id in self?.dashboard?.notificationContext(for: id) }
        SessionCompletionNotifier.isShowing = { [weak self] id in self?.isShowing(id) ?? false }
        // 見ている間に既読になった完了は対応待ちの変化を伴わないので、前面に戻ったときにも片付ける。
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let dashboard = self.dashboard else { return }
                self.applyAttention(dashboard)
            }
        }
        // 通知の文言は、画面と同じアプリ内の表示言語で出す（@AppStorage と同じ保存先を読む）。
        SessionCompletionNotifier.locale = {
            (AppLanguage(rawValue: UserDefaults.standard.string(forKey: LanguageSettings.languageKey) ?? "") ?? .system).locale
        }

        // 選択中アプリアイコンを Dock（実行中アプリのアイコン）へ再適用する。macOS には iOS の
        // setAlternateIconName が無いため、NSApp.applicationIconImage をランタイム適用する。
        applyAppIcon()

        installSignalHandlers()

        // SwiftUI exposes CommandGroupPlacement.newItem but no public Close-specific placement
        // in the local SDK interface. Intercept Cmd+W before AppKit's standard Close command so
        // the shortcut deterministically closes the selected session instead of the window.
        closeSessionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 日本語表示ではメニューの ⌘\ が ⌘¥ として登録され、英字配列の \ と一致しないため両方を横取りする。
            if event.isCommandBackslash {
                self?.router?.toggleSplit()
                return nil
            }
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
        // 見ているセッションの通知は投稿前に止めている（SessionCompletionNotifier.isShowing）。
        [.banner, .list, .sound]
    }

    /// 通知のクリックと「開く」で、Phlox を前面に出してそのセッションを選ぶ（⌘J と同じ選び方）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard [UNNotificationDefaultActionIdentifier, SessionCompletionNotifier.openActionIdentifier].contains(response.actionIdentifier),
              case let candidates = SessionCompletionNotifier.sessionIDs(from: response.notification.request.content.userInfo),
              !candidates.isEmpty else { return }
        await MainActor.run {
            // まとめは、含むうちまだ対応待ちの最も新しいセッションへ（全部済んでいれば最も新しいもの）。
            let pending = self.dashboard?.attentionSessionIDs ?? []
            self.openSession(candidates.first(where: pending.contains) ?? candidates[0])
        }
    }

    /// 前面の Phlox で見えているセッションか。単体では選択中のもの、グリッドでは表示中のタイル全部。
    private func isShowing(_ id: SessionID) -> Bool {
        guard let router, let dashboard, NSApp.isActive, !router.commonTerminalSelected,
              let window = NSApp.mainWindow, window.isVisible, !window.isMiniaturized else { return false }
        return router.viewMode == .grid ? dashboard.gridTileOrder().contains(id) : router.selectedSession == id
    }

    private func openSession(_ id: SessionID) {
        NSApp.activate()
        guard let router, dashboard?.notificationContext(for: id) != nil else { return }
        (NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        // 入力欄がフォーカスを持ったままだと、グリッドではそのタイルが選択を取り返す。
        NSApp.mainWindow?.makeFirstResponder(nil)
        router.commonTerminalSelected = false
        if router.viewMode == .grid { dashboard?.revealInGrid(id) }
        router.selectedSession = id
    }

    /// Dock バッジ（対応待ちの件数）と通知センターの片付けを、対応待ちの変化に合わせて更新する。
    private func observeAttention() {
        guard let dashboard else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        withObservationTracking {
            applyAttention(dashboard)
        } onChange: { [weak self, weak dashboard] in
            Task { @MainActor in
                guard let self, let dashboard, self.dashboard === dashboard else { return }
                self.observeAttention()
            }
        }
    }

    private func applyAttention(_ dashboard: DashboardViewModel) {
        NSApp.dockTile.badgeLabel = DockBadge.label(count: dashboard.attentionCount)
        SessionCompletionNotifier.removeDelivered(
            attention: dashboard.attentionSessionIDs,
            unseenCompletions: dashboard.unseenCompletionSessionIDs,
            includesPreviousLaunch: dashboard.hasRestoredSessions
        )
    }

    private func closeSelectedSession() -> Bool {
        performCloseSelectedSession(router: router)
    }

}

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: ProcessInfo.processInfo.environment["PHLOX_DEFAULTS_SUITE"]?.isEmpty ?? true,
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

/// 01 F「ファイル」。新規・タブ・プロジェクト ｜ 書き出し ｜ 閉じる（子タブは閉じる / 会話は削除… / グリッドは外す）。
private struct FileCommands: Commands {
    var dashboard: DashboardViewModel?
    var router: AppRouter?
    @AppStorage(LanguageSettings.languageKey) private var appLanguageRaw = AppLanguage.system.rawValue

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // 種別 × 開き方の表を開く（08: ⌘N / ⇧⌘N / ⌥⌘N を 1 つにまとめた）。失敗は画面のアラートに出る。
            Button("新規セッション…") {
                router?.newSessionTablePresented = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(dashboard?.projects.isEmpty ?? true)

            Button("新しいタブ…") {
                guard let router else { return }
                router.viewMode = .single
                router.commonTerminalSelected = false
                router.newTabChooserPresented = true
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(router?.selectedSession == nil)

            Button("ファイルを開く…") {
                guard let router, let id = router.selectedSession else { return }
                router.tabRequest = .openFile(id)
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(router?.selectedSession == nil)

            Button("プロジェクトを追加…") {
                router?.addProjectRequested = true
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(router == nil)

            Divider()

            // 対話 TUI の /export 相当。チャットセッションのみ対象（PTY は transcript を持たない）。
            Button("会話を書き出す…") {
                guard let chat = exportableChatSession(dashboard: dashboard, router: router) else { return }
                ChatTranscriptExportAction.save(session: chat, locale: (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale, showsOptions: true)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportableChatSession(dashboard: dashboard, router: router) == nil)

            Button("会話を Markdown でコピー") {
                guard let chat = exportableChatSession(dashboard: dashboard, router: router) else { return }
                ChatTranscriptExportAction.copyToPasteboard(session: chat)
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(exportableChatSession(dashboard: dashboard, router: router) == nil)

            Divider()

        }
        // 標準の「閉じる」「すべてを閉じる」をこの 1 項目に置き換える。行き先が無ければウィンドウを閉じる。
        CommandGroup(replacing: .saveItem) {
            Button(closeTitle) {
                if !performCloseSelectedSession(router: router) {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
        }
    }

    /// ⌘W の行き先で文言を変える（02 R:100）。
    private var closeTitle: LocalizedStringKey {
        guard let router else { return "閉じる" }
        switch router.tabs.closeTarget(selectedSession: router.selectedSession, viewMode: router.viewMode) {
        case .gridTile: return "グリッドから外す"
        case .session: return "セッションを削除…"
        case .childTab, nil: return "閉じる"
        }
    }
}

/// 子タブの操作（分割・次前のタブ）が効く状態。`AppRouter.toggleSplit` / `cycleChildTab` の条件と同じ。
@MainActor
private func canUseChildTabs(_ router: AppRouter?) -> Bool {
    guard let router else { return false }
    return router.viewMode == .single && !router.commonTerminalSelected && router.selectedSession != nil
}

/// 前面に出ている会話（appServer）の ViewModel。PTY セッションと、共通ターミナルを
/// 前面にしている間（会話は背後に隠れている）は対象外。
@MainActor
private func exportableChatSession(dashboard: DashboardViewModel?, router: AppRouter?) -> ChatSessionViewModel? {
    guard let dashboard,
          router?.commonTerminalSelected != true,
          let sessionID = router?.selectedSession,
          case .appServer(let chat) = dashboard.sessionNode(id: sessionID)
    else { return nil }
    return chat
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

/// 01 F「表示」。表示モード・分割 ｜ 領域とタブ ｜ 文字の大きさ。
private struct ViewCommands: Commands {
    var dashboard: DashboardViewModel?
    var router: AppRouter?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("単体") {
                router?.viewMode = .single
            }
            .keyboardShortcut("1", modifiers: [.command, .control])
            .disabled(router == nil)

            Button("グリッド") {
                router?.viewMode = .grid
            }
            .keyboardShortcut("2", modifiers: [.command, .control])
            .disabled(router == nil)

            Button("次の表示モード") {
                router?.toggleViewMode()
            }
            .keyboardShortcut("g", modifiers: [.command, .control])
            .disabled(router == nil)

            Button("右に分割して開く") { router?.toggleSplit() }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(!canUseChildTabs(router))

            Divider()

            // SwiftUI 標準のサイドバー・インスペクタのコマンドと同じ割り当て（13 Review）。
            Button("サイドバー") {
                router?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(router == nil)

            Button("インスペクタ") {
                router?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(router == nil)

            // ⌥⌘T は macOS 標準の「ツールバーを表示/隠す」と重なるため ⌃⌘T（13 Review）。
            Button("ターミナルのタブ") {
                router?.openChildTab(.terminal)
            }
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(router == nil)

            Button("変更のタブ") {
                router?.openChildTab(.changes)
            }
            .keyboardShortcut("e", modifiers: [.command, .control])
            .disabled(router?.selectedSession == nil)

            // 表示範囲バーの「レイアウト ▾」と同じ 9 種（骨格 E2・06）。
            Menu("グリッドのレイアウト") {
                ForEach(PaneLayoutPreset.allCases, id: \.self) { preset in
                    Button(LocalizedStringKey(preset.displayName)) {
                        router?.viewMode = .grid
                        dashboard?.handlePaneLayoutAction(.applyPreset(preset))
                    }
                }
            }
            .disabled(dashboard == nil)

            Divider()

            Button("文字を大きく") {
                dashboard?.adjustFontSize(by: 1, target: fontTarget)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(dashboard == nil)

            Button("文字を小さく") {
                dashboard?.adjustFontSize(by: -1, target: fontTarget)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(dashboard == nil)

            Button("実寸") {
                dashboard?.resetFontSize(target: fontTarget)
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(dashboard == nil)

            Divider()
        }
    }

    /// フォーカス中の領域（会話かターミナル）。
    private var fontTarget: DashboardViewModel.FontSizeTarget {
        let id = router?.selectedSession
        return DashboardViewModel.fontSizeTarget(
            node: id.flatMap { dashboard?.sessionNode(id: $0) },
            selectedChildTab: id.flatMap { router?.tabs.layout(for: $0).selected },
            showsCommonTerminal: router?.commonTerminalSelected ?? false
        )
    }
}

/// 01 F「セッション」。移動 ｜ 対応待ちへの返答 ｜ セッションの操作 ｜ 削除。
private struct SessionCommands: Commands {
    var dashboard: DashboardViewModel?
    var router: AppRouter?

    var body: some Commands {
        CommandMenu("セッション") {
            // 単体では上段のセッションタブ、グリッドではタイルを左上から数えて選ぶ。
            ForEach(1...9, id: \.self) { number in
                Button("セッションのタブ \(number)") { selectTab(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                    .disabled(dashboard == nil)
            }
            Button("次のタブ") { router?.cycleChildTab(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(!canUseChildTabs(router))
            Button("前のタブ") { router?.cycleChildTab(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(!canUseChildTabs(router))

            // 表示モードは変えずに選ぶ（グリッドではそのタイルがフォーカスになる）。
            Button("次の対応待ちへ") {
                guard let dashboard, let router,
                      let nextID = dashboard.nextAttentionSessionID(after: router.selectedSession) else { return }
                // 入力欄がフォーカスを持ったままだと、グリッドではそのタイルが選択を取り返す。
                NSApp.mainWindow?.makeFirstResponder(nil)
                router.selectedSession = nextID
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(!(dashboard?.hasAttention ?? false))

            Button("対応待ちの一覧") {
                router?.attentionListPresented = true
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .disabled(!(dashboard?.hasAttention ?? false))

            Button("次のセッション") { selectAdjacentSession(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(dashboard == nil)
            Button("前のセッション") { selectAdjacentSession(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(dashboard == nil)

            // グリッドのタイルを左上から数えてフォーカスする（01 F）。
            ForEach(1...9, id: \.self) { number in
                Button("タイル \(number) にフォーカス") { focusTile(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [.command, .option])
                    .disabled(router?.viewMode != .grid)
            }

            // 06 キーボード: フォーカス中のタイルを隣と入れ替える（⌥⌘⇧＋矢印）・辺の分割線を 5% 動かす（⌃⌥＋矢印）。
            ForEach(GridKeyboardMove.all.indices, id: \.self) { index in
                let move = GridKeyboardMove.all[index]
                Button(move.title) { gridKeyboardMove(move) }
                    .keyboardShortcut(move.key, modifiers: move.modifiers)
                    .disabled(router?.viewMode != .grid || router?.selectedSession == nil)
            }

            Divider()

            // 承認カードの許可 / 拒否（05 R6: 入力欄にいても修飾キー 2 つで返せる。出た直後 0.5 秒は効かない）。
            Button("許可") {
                guard let chat = exportableChatSession(dashboard: dashboard, router: router) else { return }
                Task { await chat.respondToCurrentApproval(.accept) }
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(exportableChatSession(dashboard: dashboard, router: router)?.currentReplyApproval == nil)
            Button("拒否") {
                guard let chat = exportableChatSession(dashboard: dashboard, router: router) else { return }
                Task { await chat.respondToCurrentApproval(.decline) }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(exportableChatSession(dashboard: dashboard, router: router)?.currentReplyApproval == nil)
            // 会話の中断（13 Review: Esc と同じ。ただし Esc 2 回の巻き戻しには数えない）。
            Button("中断") {
                guard let chat = exportableChatSession(dashboard: dashboard, router: router) else { return }
                Task { await chat.turnInterrupt() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!(exportableChatSession(dashboard: dashboard, router: router)?.showsProcessingIndicator ?? false))

            Divider()

            // サイドバーの行のメニューと同じ操作（03 F2・F3・F6）。キーボードだけでも届くように置く。
            Button("名前を変更…") {
                guard let id = router?.selectedSession else { return }
                router?.sidebarRequest = .renameSession(id)
            }
            .disabled(selectedNode == nil)
            Menu("別のプロジェクトへ移動") {
                if let node = selectedNode {
                    ForEach(dashboard?.projects.filter { $0.id != node.projectID } ?? []) { project in
                        Button(project.name) {
                            router?.sidebarRequest = .moveSession(node.id, project.id)
                        }
                        .disabled(dashboard?.canMoveSession(node.id) == false)
                    }
                    if dashboard?.canMoveSession(node.id) == false {
                        Text("worktree で動いているチャットは移動できません")
                    }
                    if node.pty != nil {
                        Divider()
                        Button("フォルダを選択…") {
                            router?.sidebarRequest = .changeFolder(node.id)
                        }
                    }
                }
            }
            .disabled(selectedNode == nil)
            Toggle("git worktree で隔離する", isOn: worktreeIsolation)
                .disabled(selectedProjectID == nil)

            Divider()

            Button("セッションを削除…", role: .destructive) {
                guard let id = router?.selectedSession else { return }
                router?.tabRequest = .confirmSessionDeletion(id)
            }
            .disabled(selectedNode == nil)
        }
    }

    private var selectedProjectID: ProjectID? {
        selectedNode?.projectID ?? router?.selectedProjectID
    }

    /// 選択中のセッション（無ければプロジェクト）が属するプロジェクトの隔離設定。以降に起動するセッションに効く。
    private var worktreeIsolation: Binding<Bool> {
        Binding(
            get: {
                guard let id = selectedProjectID else { return false }
                return dashboard?.projects.first { $0.id == id }?.usesWorktreeIsolation ?? false
            },
            set: { enabled in
                guard let id = selectedProjectID else { return }
                dashboard?.setWorktreeIsolationEnabled(enabled, for: id)
            }
        )
    }

    private func selectTab(_ number: Int) {
        guard let dashboard, let router else { return }
        let ids = dashboard.numberedTabSessionIDs(router: router)
        guard ids.indices.contains(number - 1) else { return }
        NSApp.mainWindow?.makeFirstResponder(nil)
        router.commonTerminalSelected = false
        router.selectedSession = ids[number - 1]
    }

    private func focusTile(_ number: Int) {
        guard let dashboard, let router, router.viewMode == .grid else { return }
        let ids = dashboard.gridTileOrder()
        guard ids.indices.contains(number - 1) else { return }
        NSApp.mainWindow?.makeFirstResponder(nil)
        router.selectedSession = ids[number - 1]
    }

    private func gridKeyboardMove(_ move: GridKeyboardMove) {
        guard let dashboard, let router, router.viewMode == .grid, let id = router.selectedSession else { return }
        if move.swaps {
            dashboard.swapGridTile(id, toward: move.direction)
        } else {
            dashboard.nudgeGridDivider(of: id, toward: move.direction)
        }
    }

    private var selectedNode: SessionNode? {
        router?.selectedSession.flatMap { dashboard?.sessionNode(id: $0) }
    }

    private func selectAdjacentSession(forward: Bool) {
        guard let dashboard, let router else { return }
        if let nextID = dashboard.adjacentSessionID(from: router.selectedSession, forward: forward) {
            router.selectedSession = nextID
        }
    }
}

/// 06 キーボードのメニュー項目（入れ替え 4 向き・分割線 4 向き）。
@MainActor
private struct GridKeyboardMove {
    let title: LocalizedStringKey
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let direction: PaneDirection
    let swaps: Bool

    static let all: [GridKeyboardMove] = [
        .init(title: "タイルを左と入れ替え", key: .leftArrow, modifiers: [.command, .option, .shift], direction: .left, swaps: true),
        .init(title: "タイルを右と入れ替え", key: .rightArrow, modifiers: [.command, .option, .shift], direction: .right, swaps: true),
        .init(title: "タイルを上と入れ替え", key: .upArrow, modifiers: [.command, .option, .shift], direction: .up, swaps: true),
        .init(title: "タイルを下と入れ替え", key: .downArrow, modifiers: [.command, .option, .shift], direction: .down, swaps: true),
        .init(title: "分割線を左へ", key: .leftArrow, modifiers: [.control, .option], direction: .left, swaps: false),
        .init(title: "分割線を右へ", key: .rightArrow, modifiers: [.control, .option], direction: .right, swaps: false),
        .init(title: "分割線を上へ", key: .upArrow, modifiers: [.control, .option], direction: .up, swaps: false),
        .init(title: "分割線を下へ", key: .downArrow, modifiers: [.control, .option], direction: .down, swaps: false),
    ]
}

private extension NSEvent {
    var isCommandW: Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && charactersIgnoringModifiers?.lowercased() == "w"
    }

    var isCommandBackslash: Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && ["\\", "¥"].contains(charactersIgnoringModifiers ?? "")
    }
}

/// 11 I1: 初期化中。段階ごとの文言（セッションの復元の件数など）は見本でも推測のため出さない。
private struct InitLoadingView: View {
    /// 1 秒以内に終わる起動では何も出さない（11 I1）。
    @State private var isShown = false

    var body: some View {
        VStack(spacing: 12) {
            AppIconBadge(showsCaution: false, size: 64)
            Text("Phlox を起動しています")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DSColor.textPrimary)
            StartupProgressBar()
                .accessibilityRepresentation { ProgressView() }
        }
        .opacity(isShown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.windowBackground)
        .task {
            try? await Task.sleep(for: .seconds(1))
            isShown = true
        }
    }
}

/// 11 I1: 幅 240・高さ 4 の進み具合の帯。段階の件数は取れないので、accent の帯が行き来する（動きを減らす設定では止める）。
private struct StartupProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var atEnd = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(DSColor.textPrimary.opacity(DSColor.isDark ? 0.10 : 0.08))
            .overlay(alignment: atEnd ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DSColor.accentFill)
                    .frame(width: 96)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .frame(width: 240, height: 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { atEnd = true }
            }
    }
}

/// 11 I2/I3: 初期化エラー。何が起きたかの説明と、原因の文（エラーの内容）を等幅で出し、
/// ログの表示・終了・再試行（既定）を置く。
private struct InitErrorView: View {
    let failure: InitFailure
    let logWritten: Bool
    let retry: () -> Void

    private var description: LocalizedStringKey? {
        switch failure {
        case .claudeNotFound: "Claude Code CLI が見つかりませんでした。次のコマンドでインストールしてください。"
        case .serverFailed: "制御用のサーバーを開始できません。"
        case .migrationFailed: "以前のバージョンのデータを移行できませんでした。データは消えていません。"
        case .legacyAppRunning: "以前のバージョンのアプリ（AgentDashboard）が起動しているため、データを移行できませんでした。データは消えていません。終了してから再試行してください。"
        case .other: nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            AppIconBadge(showsCaution: true, size: 64)
            Text("Phlox を起動できませんでした")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DSColor.textPrimary)
            if let description {
                Text(description)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: 400)
            }
            Text(verbatim: failure.log)
                .font(.system(size: 11, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(DSColor.isDark ? DSColor.textSecondary : DSColor.textPrimary.opacity(0.85))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 8) {
                Button("ログを Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([InitFailure.logURL])
                }
                .buttonStyle(.ds(.secondary))
                // 今回の失敗を書けなかったときは、古いログや無いファイルを示さない。
                .disabled(!logWritten)
                Button("終了") { NSApp.terminate(nil) }
                    .buttonStyle(.ds(.secondary, keyHint: "⌘Q"))
                    .keyboardShortcut("q", modifiers: .command)
                Button("再試行", action: retry)
                    .buttonStyle(.ds(.primary, keyHint: "⌘R"))
                    .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 48)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.windowBackground)
    }
}
