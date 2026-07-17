import Foundation
import AgentDomain
import AppBootstrap
import ControlServer
import HookServer
import MessageStore
import MobileProxy
import PTYKit
import DashboardFeature
import SessionFeature
import StructuredChatKit
import os

@MainActor
public final class CompositionRoot {
    public let environment: AppEnvironment
    public let dashboard: DashboardViewModel
    public let router: AppRouter
    public let usage: UsageMonitor
    public let appSupportMigrationOutcome: MigrationOutcome

    /// モバイル中継プロキシが実際にバインドした露出範囲（UI から接続可否を表示するために公開）。
    /// `.loopbackOnly` は「Tailscale 未検出のためモバイル接続不可（外部露出なし）」を意味する。
    /// プロキシ起動に失敗した場合は nil。
    public let mobileProxyBindMode: BindMode?

    /// モバイル専用トークンの表示・コピー・再発行 UI を駆動する ViewModel（設定画面で使用）。
    public let mobileTokenViewModel: MobileTokenViewModel

    /// モバイルトークンに紐づく安定した requester SessionID。
    /// MC-2b が特権 requester（kill 認可の親扱い）として参照するために公開する。
    /// 本タスクでは authz 判定には一切使わない（公開のみ）。
    public let mobileRequesterSessionID: SessionID

    private let controlServer: ControlServer
    private let mobileProxy: MobileProxy
    private let actionHandler: ControlActionHandler

    public init(
        onDashboardReady: (@MainActor (DashboardViewModel, PTYManager) -> Void)? = nil
    ) async throws {
        let appSupportMigrationOutcome = Self.migrateAndCleanupAppSupport()
        let hookInfra = try await Self.startHookInfrastructure()
        let claudeSettings = try Self.prepareClaudeSettings()
        let agents = try await Self.resolveAgentBinariesAndCatalog()
        let stores = try Self.createWorkspaceAndPersistenceStores()
        let deviceTokenStore = KeychainDeviceTokenStore()
        let control = try await Self.startControlServer(
            tokenStore: hookInfra.tokenStore,
            deviceTokenStore: deviceTokenStore,
            agentCatalog: agents.agentCatalog,
            savedPorts: hookInfra.savedPorts,
            hookPort: hookInfra.port
        )
        let mobileProxyResult = await Self.startMobileProxy(controlPort: control.controlPort)
        let mobileToken = try await Self.provisionMobileToken(tokenStore: hookInfra.tokenStore)
        let mobileTokenViewModel = MobileTokenViewModel(
            provisioned: mobileToken.provisioned,
            provisioner: mobileToken.mobileProvisioner,
            tokenStore: hookInfra.tokenStore,
            proxy: mobileProxyResult.proxy,
            bindMode: mobileProxyResult.bindMode,
            mobileProxyPort: mobileProxyResult.listenPort.map(Int.init)
        )
        mobileTokenViewModel.startAutoRecovery()
        let remoteSessionNotifier = Self.wireAPNsNotifications(deviceTokenStore: deviceTokenStore)
        let started = try await Self.assembleEnvironmentAndStartDashboard(
            pty: hookInfra.pty,
            hook: hookInfra.hook,
            hookURL: hookInfra.hookURL,
            claudeSettings: claudeSettings,
            agents: agents,
            stores: stores,
            controlURL: control.controlURL,
            tokenStore: hookInfra.tokenStore,
            mobileRequesterSessionID: mobileToken.provisioned.requesterSessionID,
            remoteSessionNotifier: remoteSessionNotifier,
            onDashboardReady: onDashboardReady
        )
        self.environment = started.environment
        self.dashboard = started.dashboard
        self.router = started.router
        self.usage = started.usage
        self.appSupportMigrationOutcome = appSupportMigrationOutcome
        self.mobileProxyBindMode = mobileProxyResult.bindMode
        self.mobileTokenViewModel = mobileTokenViewModel
        self.mobileRequesterSessionID = mobileToken.provisioned.requesterSessionID
        self.controlServer = control.controlServer
        self.mobileProxy = mobileProxyResult.proxy
        self.actionHandler = control.actionHandler
        control.actionHandler.dashboard = started.dashboard
        await started.dashboard.start()
        Self.applyRemoteSessionNotifier(remoteSessionNotifier, to: started.dashboard)
        started.usage.start()
    }

    // MARK: - init フェーズ（監査 G の 9 区分）

    /// フェーズ 1: AppSupport 移行 + レガシー掃除
    private static func migrateAndCleanupAppSupport() -> MigrationOutcome {
        let outcome = migrateAppSupportIfNeeded()
        // 撤去済みの「グローバル statusLine 設置」(②-A) が過去に書き込んだ設定を起動時に一度掃除する
        // （manifest があれば元へ復元し、Phlox 由来のラッパー/manifest を除去。孤立防止のため残す処理）。
        ClaudeGlobalStatusLineCleanup.cleanupLeftoverInstall()
        return outcome
    }

    /// フェーズ 2: Hook 基盤起動
    private static func startHookInfrastructure() async throws -> (
        pty: PTYManager,
        tokenStore: SessionTokenStore,
        hook: HookServer,
        hookURL: URL,
        port: Int,
        savedPorts: SavedPorts?
    ) {
        let pty = PTYManager()
        // hook POST の認証に使う token↔session ストア。HookServer より前に生成し注入する
        // （無認証の hook POST による偽 stop/idle 注入を防ぐ・CWE-306）。
        let tokenStore = SessionTokenStore()
        let hook = HookServer(tokenStore: tokenStore)
        let savedPorts = (try? Self.portsURL()).flatMap(SavedPorts.load(from:))
        let port = try await hook.start(preferredPort: savedPorts?.hookPort ?? 0)
        guard let url = URL(string: "http://127.0.0.1:\(port)/hook") else {
            throw CompositionError.invalidHookURL
        }
        return (pty, tokenStore, hook, url, port, savedPorts)
    }

    /// フェーズ 3: Claude 設定・statusline 生成
    private static func prepareClaudeSettings() throws -> (
        settingsURL: URL,
        restrictedSettingsURL: URL,
        claudeUsageRateLimitsURL: URL
    ) {
        let claudeUsageRateLimitsURL = try Self.claudeUsageRateLimitsURL()
        let statusLineWrapperURL = try Self.claudeStatusLineWrapperURL()
        try Self.writeClaudeStatusLineWrapper(
            wrapperURL: statusLineWrapperURL,
            rateLimitsURL: claudeUsageRateLimitsURL
        )
        let statusLineCommand = "/bin/sh \(ShellQuoting.singleQuoted(statusLineWrapperURL.path))"
        let settingsURL = try Self.writeClaudeSettings(bypass: true, statusLineCommand: statusLineCommand)
        let restrictedSettingsURL = try Self.writeClaudeSettings(bypass: false, statusLineCommand: statusLineCommand)
        return (settingsURL, restrictedSettingsURL, claudeUsageRateLimitsURL)
    }

    /// フェーズ 4: エージェントカタログ・バイナリ解決
    private static func resolveAgentBinariesAndCatalog() async throws -> (
        agentCatalog: AgentCatalog,
        claudeBinaryPath: String,
        pathEnvironment: String,
        agentBinaryPaths: [AgentKind: String],
        customAgentBinaryPaths: [String: String]
    ) {
        let customDescriptors = CustomAgentRegistryLoader.loadDescriptors()
        let agentCatalog = AgentCatalog(customDescriptors: customDescriptors)
        // 重い login shell 起動（PATH 解決の 1 回のみ）をメインアクター外で実行し、
        // 起動中のメインスレッド凍結（InitLoadingView のスピナー停止）を避ける。
        let resolvedBinaries = await Task.detached {
            BinaryPathResolver.resolveCLIBinaries(customDescriptors: customDescriptors)
        }.value
        guard let claudeBinaryPath = resolvedBinaries.claudeBinaryPath else {
            throw CompositionError.claudeNotFound
        }
        return (
            agentCatalog,
            claudeBinaryPath,
            resolvedBinaries.pathEnvironment,
            resolvedBinaries.agentBinaryPaths,
            resolvedBinaries.customAgentBinaryPaths
        )
    }

    /// フェーズ 5: ワークスペース・永続化ストア生成
    private static func createWorkspaceAndPersistenceStores() throws -> (
        workspaceURL: URL,
        messageStore: SQLiteMessageStore,
        projectStore: JSONProjectStore,
        sessionStore: JSONSessionStore
    ) {
        let workspaceURL = try Self.ensureWorkspaceDirectory()
        // tokenStore は HookServer より前で単一インスタンスを生成済み。ここでは再宣言せず、
        // 同一インスタンスを ControlServer・MobileProvisioner・AppEnvironment と共有する
        // （HookServer が参照するストアと register 先を一致させる＝正当 hook が 401 で落ちない）。
        let messageStore = try SQLiteMessageStore(databaseURL: Self.messagesDatabaseURL())
        let projectStore = JSONProjectStore(fileURL: try Self.projectsStoreURL())
        let sessionStore = JSONSessionStore(fileURL: try Self.sessionsStoreURL())
        return (workspaceURL, messageStore, projectStore, sessionStore)
    }

    /// フェーズ 6: ControlServer 起動
    private static func startControlServer(
        tokenStore: SessionTokenStore,
        deviceTokenStore: any DeviceTokenStore,
        agentCatalog: AgentCatalog,
        savedPorts: SavedPorts?,
        hookPort: Int
    ) async throws -> (
        controlServer: ControlServer,
        actionHandler: ControlActionHandler,
        controlURL: URL,
        controlPort: Int
    ) {
        let actionHandler = ControlActionHandler(deviceTokenStore: deviceTokenStore)
        let controlServer = ControlServer(tokenStore: tokenStore, agentCatalog: agentCatalog) { [actionHandler] req in
            await actionHandler.handle(req)
        }
        let controlPort = try await controlServer.start(preferredPort: savedPorts?.controlPort ?? 0)
        guard let controlURL = URL(string: "http://127.0.0.1:\(controlPort)") else {
            throw CompositionError.invalidHookURL
        }
        if let portsURL = try? Self.portsURL() {
            try? SavedPorts(hookPort: UInt16(hookPort), controlPort: UInt16(controlPort)).save(to: portsURL)
        }
        return (controlServer, actionHandler, controlURL, controlPort)
    }

    /// フェーズ 7: MobileProxy 起動
    private static func startMobileProxy(controlPort: Int) async -> (
        proxy: MobileProxy,
        bindMode: BindMode?,
        listenPort: UInt16?
    ) {
        // モバイル中継プロキシ: 既定は Tailscale IF の固定ポート(既定 8765)で待ち受け、受けた HTTP を
        // 127.0.0.1:<controlPort>(ControlServer)へ無改変で中継する。controlPort はメモリから直接渡す。
        // secure-by-default: Tailscale 未検出時は loopback(127.0.0.1)限定にフォールバックし、
        // 全 IF(0.0.0.0)へは決して暗黙バインドしない(fail-closed)。露出範囲は BindMode で可観測。
        // 起動失敗(ポート使用中等)はアプリ起動を妨げないよう warning ログに留めて続行する。
        let mobileProxy = MobileProxy(targetPort: UInt16(controlPort))
        var resolvedBindMode: BindMode?
        var resolvedListenPort: UInt16?
        do {
            let listenPort = try await mobileProxy.start()
            resolvedListenPort = listenPort
            let mode = await mobileProxy.bindMode
            resolvedBindMode = mode
            switch mode {
            case .tailscale(let ip):
                Self.proxyLogger.info("Mobile proxy listening on Tailscale \(ip, privacy: .private):\(listenPort, privacy: .public) -> control port \(controlPort, privacy: .public)")
            case .explicitHost(let host):
                Self.proxyLogger.info("Mobile proxy listening on \(host, privacy: .private):\(listenPort, privacy: .public) -> control port \(controlPort, privacy: .public)")
            case .loopbackOnly:
                // fail-closed: モバイルからは到達不可。warning ではなく状態が分かる形で明示する。
                Self.proxyLogger.warning("Mobile connection unavailable (Tailscale not detected): proxy bound to loopback only (127.0.0.1:\(listenPort, privacy: .public)). No external exposure.")
            case .none:
                break
            }
        } catch {
            Self.proxyLogger.warning("Mobile proxy failed to start: \(String(describing: error), privacy: .public)")
        }
        return (mobileProxy, resolvedBindMode, resolvedListenPort)
    }

    /// フェーズ 8: モバイルトークン供給
    private static func provisionMobileToken(
        tokenStore: SessionTokenStore
    ) async throws -> (
        mobileProvisioner: MobileTokenProvisioner,
        provisioned: ProvisionedMobileToken
    ) {
        // モバイル専用 Bearer トークンを Keychain からロード（初回は生成・永続化）し、
        // 安定した requester SessionID へ register する。token 値はログに残さない。
        // Keychain アクセス失敗時はアプリ起動を妨げないよう、一時的なインメモリへフォールバックして続行する。
        let mobileProvisioner: MobileTokenProvisioner
        let provisioned: ProvisionedMobileToken
        #if DEBUG
        // PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1: Keychain に一切触れずインメモリで供給する。
        // adhoc 署名のテストビルドはビルドごとに Designated Requirement が変わり、
        // Keychain 許可ダイアログが毎回再発して UI 自動化を塞ぐため、その回避用。
        // この分岐自体が Debug ビルドにのみ存在し、Release では env に関わらず Keychain 経路のみを通る。
        if ProcessInfo.processInfo.environment["PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN"] == "1" {
            Self.tokenLogger.info("Mobile token: ephemeral in-memory store (test build; keychain untouched)")
            let ephemeral = MobileTokenProvisioner(store: InMemoryMobileTokenStore())
            provisioned = try ephemeral.loadOrProvision()
            mobileProvisioner = ephemeral
        } else {
            do {
                let keychainProvisioner = MobileTokenProvisioner(store: KeychainMobileTokenStore())
                provisioned = try keychainProvisioner.loadOrProvision()
                mobileProvisioner = keychainProvisioner
            } catch {
                Self.tokenLogger.warning("Mobile token provisioning failed; using ephemeral token: \(String(describing: error), privacy: .public)")
                let fallback = MobileTokenProvisioner(store: InMemoryMobileTokenStore())
                provisioned = try fallback.loadOrProvision()
                mobileProvisioner = fallback
            }
        }
        #else
        do {
            let keychainProvisioner = MobileTokenProvisioner(store: KeychainMobileTokenStore())
            provisioned = try keychainProvisioner.loadOrProvision()
            mobileProvisioner = keychainProvisioner
        } catch {
            Self.tokenLogger.warning("Mobile token provisioning failed; using ephemeral token: \(String(describing: error), privacy: .public)")
            let fallback = MobileTokenProvisioner(store: InMemoryMobileTokenStore())
            provisioned = try fallback.loadOrProvision()
            mobileProvisioner = fallback
        }
        #endif
        await mobileProvisioner.register(provisioned, into: tokenStore)
        Self.tokenLogger.info("Mobile token registered to requester session \(provisioned.requesterSessionID.rawValue.uuidString, privacy: .private)")
        return (mobileProvisioner, provisioned)
    }

    /// フェーズ 9: APNs 通知ブリッジ配線
    private static func wireAPNsNotifications(
        deviceTokenStore: any DeviceTokenStore
    ) -> any RemoteSessionNotifier {
        APNsNotificationBridge.configuredFromEnvironment(deviceTokenStore: deviceTokenStore)
    }

    /// フェーズ 10: AppEnvironment 組み立て・DashboardViewModel 起動
    private static func assembleEnvironmentAndStartDashboard(
        pty: PTYManager,
        hook: HookServer,
        hookURL: URL,
        claudeSettings: (settingsURL: URL, restrictedSettingsURL: URL, claudeUsageRateLimitsURL: URL),
        agents: (
            agentCatalog: AgentCatalog,
            claudeBinaryPath: String,
            pathEnvironment: String,
            agentBinaryPaths: [AgentKind: String],
            customAgentBinaryPaths: [String: String]
        ),
        stores: (
            workspaceURL: URL,
            messageStore: SQLiteMessageStore,
            projectStore: JSONProjectStore,
            sessionStore: JSONSessionStore
        ),
        controlURL: URL,
        tokenStore: SessionTokenStore,
        mobileRequesterSessionID: SessionID,
        remoteSessionNotifier: any RemoteSessionNotifier,
        onDashboardReady: (@MainActor (DashboardViewModel, PTYManager) -> Void)?
    ) async throws -> (
        environment: AppEnvironment,
        dashboard: DashboardViewModel,
        router: AppRouter,
        usage: UsageMonitor
    ) {
        let env = AppEnvironment(
            pty: pty,
            hook: hook,
            hookURL: hookURL,
            claudeSettingsURL: claudeSettings.settingsURL,
            claudeSettingsRestrictedURL: claudeSettings.restrictedSettingsURL,
            hookDispatcherPath: Self.hookDispatcherPath,
            claudeBinaryPath: agents.claudeBinaryPath,
            pathEnvironment: agents.pathEnvironment,
            claudeUsageRateLimitsURL: claudeSettings.claudeUsageRateLimitsURL,
            workspaceDirectory: stores.workspaceURL,
            agentBinaryPaths: agents.agentBinaryPaths,
            customAgentBinaryPaths: agents.customAgentBinaryPaths,
            agentCatalog: agents.agentCatalog,
            controlURL: controlURL,
            tokenStore: tokenStore,
            messages: stores.messageStore,
            projects: stores.projectStore,
            sessions: stores.sessionStore,
            transcriptStore: FileTranscriptStore(),
            cliPath: Self.cliPath
        )
        let dashboard = DashboardViewModel(
            environment: env,
            livePIDProvider: { id in await pty.pid(for: id) }
        )
        let usage = UsageMonitor(
            environment: env,
            sessions: Self.claudeUsageQueryingSessions(dashboard: dashboard)
        )
        ControlDashboardSupport.usageMonitor = usage
        // spawn 済みセッションの live pid を PTYManager（actor）から読み出して descriptor へ
        // 永続化する seam を配線する。これがないと sessions.json の pid が常に nil になり、
        // 起動時 reconcile の生存孤児 reap が production で発火しない。pid 未取得時は nil。
        onDashboardReady?(dashboard, pty)
        installRemoteSessionNotifier(remoteSessionNotifier, on: dashboard)
        // MC-2b: モバイルトークンの安定 requester を「特権 requester」として認可へ配線する。
        // この requester は cascade delete を含む全 remove を無条件で許可される
        // （脅威モデル「トークン漏洩 = Mac 全権」と整合。特権の範囲は remove のみ）。
        dashboard.setPrivilegedRequester(mobileRequesterSessionID)
        let router = AppRouter()
        return (env, dashboard, router, usage)
    }

    private static func installRemoteSessionNotifier(
        _ notifier: any RemoteSessionNotifier,
        on dashboard: DashboardViewModel
    ) {
        applyRemoteSessionNotifier(notifier, to: dashboard)
        DashboardSessionSpawnHooks.setHandler(
            id: DashboardSessionSpawnHooks.remoteSessionNotifierHookID,
            on: dashboard
        ) { [weak dashboard] _ in
            guard let dashboard else { return }
            applyRemoteSessionNotifier(notifier, to: dashboard)
        }
    }

    private static func applyRemoteSessionNotifier(
        _ notifier: any RemoteSessionNotifier,
        to dashboard: DashboardViewModel
    ) {
        for session in dashboard.sessions {
            session.remoteSessionNotifier = notifier
        }
        // チャット型（appServer）にも同じ notifier を配線する（PTY 限定だった注入漏れの是正）。
        for node in dashboard.sessionNodes {
            node.appServer?.remoteSessionNotifier = notifier
        }
    }

    private static let proxyLogger = Logger(subsystem: "com.phlox.Phlox", category: "MobileProxy")
    private static let tokenLogger = Logger(subsystem: "com.phlox.Phlox", category: "MobileToken")

    private static func portsURL() throws -> URL {
        try phloxAppSupportURL().appendingPathComponent("ports.json")
    }

    /// `claude --settings` に渡す hooks 設定 JSON を生成し、Application Support 配下に書き出す。
    static func writeClaudeSettings(bypass: Bool, statusLineCommand: String) throws -> URL {
        let fm = FileManager.default
        let appSupport = try phloxAppSupportURL()
        try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let settings = ClaudeSettingsGenerator.settings(
            defaultMode: bypass ? "bypassPermissions" : "default",
            dispatcher: Self.hookDispatcherPath,
            statusLineCommand: statusLineCommand
        )

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        let fileName = bypass ? "hooks.json" : "hooks-restricted.json"
        let url = appSupport.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writeClaudeStatusLineWrapper(wrapperURL: URL, rateLimitsURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: wrapperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: rateLimitsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let script = """
        #!/bin/sh
        input=$(cat)
        rate_limits_file=\(ShellQuoting.singleQuoted(rateLimitsURL.path))
        wrapper_path=\(ShellQuoting.singleQuoted(wrapperURL.path))
        user_settings="${HOME:-}/.claude/settings.json"

        if command -v python3 >/dev/null 2>&1; then
          STATUSLINE_INPUT="$input" RATE_LIMITS_FILE="$rate_limits_file" python3 - <<'PY'
        import json
        import os
        import tempfile
        import time

        payload = os.environ.get("STATUSLINE_INPUT", "")
        output = os.environ.get("RATE_LIMITS_FILE", "")
        try:
            data = json.loads(payload)
            rate_limits = data.get("rate_limits")
            if rate_limits and output:
                directory = os.path.dirname(output)
                os.makedirs(directory, exist_ok=True)
                fd, tmp = tempfile.mkstemp(prefix=".claude-usage.", dir=directory)
                with os.fdopen(fd, "w") as handle:
                    json.dump(
                        {"ts": time.time(), "rate_limits": rate_limits},
                        handle,
                        separators=(",", ":"),
                    )
                os.replace(tmp, output)
        except Exception:
            pass
        PY
        fi

        user_command=""
        if [ -f "$user_settings" ]; then
          if command -v python3 >/dev/null 2>&1; then
            user_command=$(STATUSLINE_SETTINGS="$user_settings" python3 - <<'PY'
        import json
        import os

        try:
            with open(os.environ["STATUSLINE_SETTINGS"], "r") as handle:
                settings = json.load(handle)
            command = settings.get("statusLine", {}).get("command", "")
            if isinstance(command, str):
                print(command, end="")
        except Exception:
            pass
        PY
        )
          elif command -v plutil >/dev/null 2>&1; then
            user_command=$(plutil -extract statusLine.command raw -o - "$user_settings" 2>/dev/null || true)
          fi
        fi

        if [ -n "$user_command" ] && [ "$user_command" != "$wrapper_path" ]; then
          printf '%s' "$input" | /bin/sh -c "$user_command"
        fi
        """

        try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
    }

    /// AppSupport 配下にセッション別ワークスペースのルートを作成する。
    /// CWD を $HOME や .app バンドル内にすると iCloud Drive・/Volumes 等を CLI が
    /// 走査して不要な TCC ダイアログが出るため、隔離されたルート配下に各セッションを置く。
    private static func ensureWorkspaceDirectory() throws -> URL {
        let fm = FileManager.default
        let workspace = try phloxAppSupportURL()
            .appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private static func messagesDatabaseURL() throws -> URL {
        let appSupport = try phloxAppSupportURL()
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("messages.sqlite")
    }

    private static func projectsStoreURL() throws -> URL {
        let appSupport = try phloxAppSupportURL()
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("projects.json")
    }

    private static func sessionsStoreURL() throws -> URL {
        let appSupport = try phloxAppSupportURL()
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("sessions.json")
    }

    private static func claudeUsageRateLimitsURL() throws -> URL {
        let appSupport = try phloxAppSupportURL()
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("claude-usage-rate-limits.json")
    }

    private static func claudeStatusLineWrapperURL() throws -> URL {
        let appSupport = try phloxAppSupportURL()
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("claude-statusline-wrapper.sh")
    }

    /// flavor に応じた Application Support ルートの URL を返す（ディレクトリは作成しない）。
    private static func phloxAppSupportURL() throws -> URL {
        try AppSupportLocator.appSupportDirectoryURL()
    }

    nonisolated static func migrateAppSupportIfNeeded(
        fileManager: FileManager = .default
    ) -> MigrationOutcome {
        guard AppFlavor.current.runsLegacyMigration else {
            return .skippedExistingData(reason: "legacy migration disabled for debug flavor")
        }
        do {
            let root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return migrateAppSupportIfNeeded(
                from: root.appendingPathComponent("AgentDashboard", isDirectory: true),
                to: root.appendingPathComponent(AppFlavor.current.appSupportDirectoryName, isDirectory: true),
                fileManager: fileManager
            )
        } catch {
            return .failed(reason: "Application Support URL could not be resolved: \(error.localizedDescription)")
        }
    }

    @discardableResult
    nonisolated static func migrateAppSupportIfNeeded(
        from oldURL: URL,
        to newURL: URL,
        fileManager: FileManager = .default
    ) -> MigrationOutcome {
        AppSupportMigrator.migrateAppSupportIfNeeded(
            from: oldURL,
            to: newURL,
            fileManager: fileManager,
            options: AppSupportMigrationOptions()
        )
    }

    /// Debug ビルドで scripts/ を解決する際のリポジトリルート既定値。
    /// このファイル（App/ 直下）の 2 階層上 = リポジトリルート。コードを別パッケージへ
    /// 移す場合はこの既定値に依存せず、呼び出し側からルートを注入すること。
    static let defaultRepositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// scripts ディレクトリ内の実行ファイルパスを実行形態に応じて解決する。
    /// Debug ではリポジトリ内、Release ではアプリバンドル同梱リソース内を参照する。
    private static func scriptPath(_ name: String, repositoryRoot: URL = defaultRepositoryRoot) -> String {
        #if DEBUG
            return repositoryRoot.appendingPathComponent("scripts/\(name)").path
        #else
            let resourceRoot = Bundle.main.resourcePath ?? Bundle.main.bundlePath
            return URL(fileURLWithPath: resourceRoot)
                .appendingPathComponent("scripts/\(name)")
                .path
        #endif
    }

    private static let hookDispatcherPath = scriptPath("hook-dispatcher.sh")

    static let cliPath = scriptPath("phlox")

    private static func claudeUsageQueryingSessions(
        dashboard: DashboardViewModel
    ) -> @Sendable () async -> [any UsageQuerying] {
        { @Sendable in
            await MainActor.run {
                Self.liveClaudeAppServerUsageClients(in: dashboard)
            }
        }
    }

    @MainActor
    private static func liveClaudeAppServerUsageClients(
        in dashboard: DashboardViewModel
    ) -> [any UsageQuerying] {
        dashboard.sessionNodes.compactMap { node -> (any UsageQuerying)? in
            guard let chat = node.appServer,
                  chat.agentRef.builtinKind == .claudeCode,
                  Self.isLiveChatSession(chat.status)
            else { return nil }
            return chat.usageQuerying
        }
    }

    private static func isLiveChatSession(_ status: SessionStatus) -> Bool {
        switch status {
        case .starting, .idle, .running, .awaitingApproval:
            true
        case .completed, .error:
            false
        }
    }

    public enum CompositionError: Error {
        case invalidHookURL
        case claudeNotFound
    }
}
