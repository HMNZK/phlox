import AgentDomain
import AppBootstrap
import AppKit
import ClaudeAgentKit
import DashboardFeature
import Darwin
import Foundation
import PTYKit
import StructuredChatKit
import TerminalUI

@MainActor
final class SessionRuntimeHost: NSObject, NSApplicationDelegate {
    private let lease: SessionRuntimeLease
    private var discovery: SessionRuntimeDiscovery
    private var composition: CompositionRoot?
    private var dashboard: DashboardViewModel?
    private var pty: PTYManager?
    private var usageProcess: ClaudeUsageProcess?
    private var signalSources: [DispatchSourceSignal] = []
    private var startupTask: Task<Void, Never>?
    private var stopping = false
    private var handingOver = false
    private var desktopTransport: SessionRuntimeTransport?
    /// 停止処理全体の上限。PTY 終了（cleanupTimeout 5秒）と transcript flush（3秒）が収まる余裕を持たせる。
    nonisolated private static let shutdownTimeout: Duration = .seconds(10)
    /// 停止処理が戻らなくても exit に到達させる。MainActor に依存しないキューで発火する。
    nonisolated private let shutdownDeadline = ShutdownDeadline(
        timeout: SessionRuntimeHost.shutdownTimeout,
        queue: DispatchQueue(label: "com.phlox.session-runtime.shutdown-deadline"),
        exit: { exit($0) }
    )

    private init(lease: SessionRuntimeLease) {
        self.lease = lease
        self.discovery = SessionRuntimeDiscovery(storeURL: lease.storeURL, assetsRoot: CompositionRoot.runtimeAssetsRoot)
        self.discovery.runtimeBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        self.discovery.supportsHandover = true
    }

    static func run() {
        do {
            let lease = try migrateAndAcquireLease()
            let host = SessionRuntimeHost(lease: lease)
            try host.lease.publish(host.discovery)
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.delegate = host
            PhloxApp.configureSessionDefaults()
            // GUI launcher の端末や親プロセスの切断を host 終了として扱わない。
            signal(SIGHUP, SIG_IGN)
            host.signalSources = TerminationSignalHandlers.install(
                signals: [SIGTERM, SIGINT],
                queue: DispatchQueue(label: "com.phlox.session-runtime.signals")
            ) { [weak host] in
                // MainActor が詰まっていても期限だけは先に張る（requestShutdown 内でも張るが 2 回目は無視される）。
                host?.shutdownDeadline.arm(exitCode: 0)
                Task { @MainActor in host?.requestShutdown(exitCode: 0) }
            }
            host.startupTask = Task { await host.start() }
            withExtendedLifetime(host) { app.run() }
        } catch {
            FileHandle.standardError.write(Data("Session runtime could not start: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func migrateAndAcquireLease() throws -> SessionRuntimeLease {
        let storeURL = try SessionRuntimeLease.resolvedStoreURL()
        let explicitStore = ProcessInfo.processInfo.environment["PHLOX_DATA_DIR"]?.isEmpty == false
        if !explicitStore, !FileManager.default.fileExists(atPath: storeURL.path) {
            let outcome = CompositionRoot.migrateAppSupportIfNeeded()
            if let reason = outcome.startupFailureReason {
                throw CompositionRoot.CompositionError.migrationFailed(reason: reason)
            }
        }
        return try SessionRuntimeLease(storeURL: storeURL)
    }

    private func start() async {
        do {
            try TerminalCoordinator.configureRuntimeImageStore(
                directory: lease.directoryURL.appendingPathComponent("images-\(discovery.generation.uuidString)", isDirectory: true),
                writable: true
            )
            let explicitStore = ProcessInfo.processInfo.environment["PHLOX_DATA_DIR"]?.isEmpty == false
            let root = try await CompositionRoot(
                migrationEnabled: !explicitStore,
                worktreeRecreationConfirmer: { [weak self] path, _, _ in
                    self?.discovery.interactionFailure = "Worktree recreation requires a graphical confirmation: \(path)"
                    self?.publishDiscovery()
                    return false
                },
                onDashboardReady: { [weak self] dashboard, pty, usageProcess in
                    self?.dashboard = dashboard
                    self?.pty = pty
                    self?.usageProcess = usageProcess
                }
            )
            composition = root
            let transport = try SessionRuntimeTransport(
                generation: discovery.generation, storeURL: lease.storeURL,
                snapshot: {
                    var snapshot = try root.dashboard.makeRuntimeSnapshot()
                    snapshot.usage = root.usage.makeRuntimeSnapshot()
                    return snapshot
                }, overview: {
                    var overview = root.dashboard.makeRuntimeOverview()
                    overview.usage = root.usage.makeRuntimeSnapshot().boundedForOverview()
                    return overview
                }, content: { request in
                    try await root.dashboard.runtimeChatReadContent(for: request)
                }, supportsChatReadModel: true, command: { command in
                    if case .usage(let usageCommand) = command {
                        try await root.usage.performRuntimeCommand(usageCommand)
                        return .none
                    }
                    return try await root.dashboard.performRuntimeCommand(command)
                }, applicationSnapshot: {
                    try JSONEncoder().encode(SessionRuntimeApplicationSnapshot(
                        pathEnvironment: root.environment.pathEnvironment,
                        claudeBinaryPath: root.environment.claudeBinaryPath,
                        hookDispatcherPath: root.environment.hookDispatcherPath,
                        mobile: root.mobileTokenViewModel.makeRuntimeSnapshot(),
                        models: Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, AgentModelCatalog.models(for: $0)) })
                    ))
                }, applicationCommand: { [weak self] data in
                    let command = try JSONDecoder().decode(SessionRuntimeApplicationCommand.self, from: data)
                    let reply: SessionRuntimeApplicationReply
                    switch command {
                    case .mobile(let command): reply = .mobile(try await root.mobileTokenViewModel.performRuntimeCommand(command))
                    case .preferences(let values):
                        try SessionRuntimePreferences.apply(values)
                        root.usage.usageSettingsChanged()
                        reply = .preferencesApplied
                    case .handover(let bundlePath):
                        guard let self else { throw SessionRuntimeConnectionError.rejected("実行サービスは終了処理中です。") }
                        reply = try await self.requestHandover(bundlePath: bundlePath)
                    }
                    return try JSONEncoder().encode(reply)
                }
            )
            desktopTransport = transport
            discovery.desktopURL = try await transport.start()
            discovery.controlURL = root.environment.controlURL
            if !stopping { discovery.state = .ready }
            publishDiscovery()
        } catch {
            discovery.state = .failed
            discovery.failure = String(describing: error)
            publishDiscovery()
            FileHandle.standardError.write(Data("Session runtime initialization failed: \(error)\n".utf8))
            requestShutdown(exitCode: 1)
        }
    }

    // MARK: - 計画的な更新（ADR 0233）

    /// 切り替え要求。延期できるかの確認だけを同期で行い、実際の切り替えは返信の後に走らせる
    /// （この要求自身を、後で止める受付の「処理中」に含めて自己待ちしない）。
    private func requestHandover(bundlePath: String) async throws -> SessionRuntimeApplicationReply {
        guard !stopping, !handingOver, let dashboard, composition != nil else {
            return .handoverDeferred(["更新または終了の処理中です"])
        }
        let bundleURL = URL(fileURLWithPath: bundlePath).standardizedFileURL.resolvingSymlinksInPath()
        let cache = lease.storeURL.appendingPathComponent("session-runtime-bundles", isDirectory: true).path + "/"
        guard bundleURL.path.hasPrefix(cache), bundleURL.pathExtension == "app" else {
            throw SessionRuntimeConnectionError.rejected("更新先が管理された場所にありません。")
        }
        let format = Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "PhloxHandoverFormat") as? Int
        guard format == HandoverCheckpoint.formatVersion else {
            return .handoverDeferred(["新版は引き継ぎ形式が一致しないため、動いている作業が終わってから切り替えます"])
        }
        let reasons = await dashboard.handoverDeferralReasons()
        guard reasons.isEmpty else {
            discovery.updateStatus = "更新を延期しました: " + reasons.joined(separator: " / ")
            publishDiscovery()
            return .handoverDeferred(reasons)
        }
        handingOver = true
        // 前回の延期・中止の案内を消す（画面側が、新しい要求の結果として古い案内を拾わないように）。
        discovery.updateStatus = nil
        publishDiscovery()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.performHandover(bundleURL: bundleURL)
        }
        return .handoverStarted
    }

    /// 確定点を作り、不可逆の切り替えをする。コミット前の失敗は全て元に戻す（何も止めない・何も二重にしない）。
    private func performHandover(bundleURL: URL) async {
        guard let dashboard, let root = composition, !stopping else { handingOver = false; return }
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: bundleURL, storeURL: lease.storeURL)
        let ticket: SessionRuntimeLauncher.ReplacementTicket
        do { ticket = try launcher.prepareReplacement() } catch {
            failHandover("新版を確認できません: \(error)")
            return
        }
        // 閉じる前に始まったholderの起動が終わるまで待つ（確定点から漏れる子を作らない）。終わらなければ中止する。
        let drained = await dashboard.closeHandoverGateAndDrain()
        // 確定点を書いた後の中止では、自分が書いた確定点を消す（次のホスト起動が古い確定点を採用しないように）。
        var writtenCheckpointDirectory: URL?
        func abort(_ message: String) async {
            if let directory = writtenCheckpointDirectory {
                do { try HandoverCheckpointStore.discard(sourceGeneration: discovery.generation.uuidString, directory: directory) } catch {
                    FileHandle.standardError.write(Data("Session runtime handover checkpoint discard failed: \(error)\n".utf8))
                }
            }
            await dashboard.cancelHandoverEntries()
            dashboard.openHandoverGate()
            launcher.abandonReplacement(ticket)
            failHandover(message)
        }
        guard drained else { await abort("起動中の実行が終わらないため中止しました"); return }
        let reasons = await dashboard.handoverDeferralReasons()
        guard reasons.isEmpty else { await abort("更新を延期しました: " + reasons.joined(separator: " / ")); return }
        let entries: [DashboardHandoverEntry]
        do { entries = try await dashboard.prepareHandoverEntries() } catch {
            await abort("引き継ぎの準備に失敗しました: \(error)")
            return
        }
        let unmanaged = dashboard.unmanagedHolderSessions(excluding: entries)
        guard unmanaged.isEmpty else { await abort("準備中に起動した実行があるため中止しました"); return }
        await AppDelegate.flushChatTranscriptsForTermination(dashboard: dashboard, timeout: AppDelegate.transcriptFlushTimeout)
        // 子は環境のトークンでhook/Controlへ届くので、新ホストへ同じトークンを渡す（sessions.jsonには無い）。
        var sessions: [HandoverSession] = []
        for entry in entries {
            sessions.append(HandoverSession(
                sessionID: entry.sessionID.rawValue.uuidString, agent: entry.agent,
                holder: entry.preparation.holder, appliedSeq: entry.preparation.appliedSeq,
                clientState: entry.preparation.clientState,
                token: await root.environment.tokenStore.token(for: entry.sessionID)))
        }
        // 確定点は書く前に停止の有無を確かめる（書いた後の中止は確定点を消す必要がある）。
        guard !stopping else { await abort("終了処理中のため中止しました"); return }
        do {
            let checkpoint = HandoverCheckpoint(
                sourceGeneration: discovery.generation.uuidString,
                hookPort: root.environment.hookURL.port, controlPort: root.environment.controlURL.port,
                sessions: sessions)
            let directory = try CompositionRoot.handoverDirectory()
            try HandoverCheckpointStore.write(checkpoint, directory: directory)
            writtenCheckpointDirectory = directory
        } catch {
            await abort("確定点を保存できません: \(error)")
            return
        }
        guard !stopping else { await abort("終了処理中のため中止しました"); return }
        // ---- 不可逆（ここから先は子もholderも終了させない。失敗しても次のホスト起動が確定点を採用する） ----
        discovery.state = .stopping
        publishDiscovery()
        await dashboard.commitHandoverEntries(entries)
        _ = await root.stopAcceptingForHandover(timeout: .seconds(3))
        await desktopTransport?.stop()
        do {
            _ = try launcher.launchReplacement(ticket, releasing: lease)
        } catch {
            FileHandle.standardError.write(Data("Session runtime handover launch failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }

    private func failHandover(_ message: String) {
        handingOver = false
        discovery.updateStatus = message
        publishDiscovery()
        FileHandle.standardError.write(Data("Session runtime handover aborted: \(message)\n".utf8))
    }

    private func publishDiscovery() {
        do {
            try lease.publish(discovery)
        } catch {
            FileHandle.standardError.write(Data("Session runtime discovery write failed: \(error)\n".utf8))
        }
    }

    private func requestShutdown(exitCode: Int32) {
        guard !stopping else { return }
        stopping = true
        shutdownDeadline.arm(exitCode: exitCode)
        if discovery.state != .failed { discovery.state = .stopping }
        publishDiscovery()
        Task {
            await startupTask?.value
            let sessions = dashboard?.sessionNodes.compactMap(\.appServer) ?? []
            let stopPTY = Task {
                await usageProcess?.shutdown()
                await pty?.terminateAllAndWait(timeout: AppDelegate.cleanupTimeout)
            }
            await AppDelegate.flushChatTranscriptsForTermination(
                dashboard: dashboard,
                timeout: AppDelegate.transcriptFlushTimeout
            )
            await withTaskGroup(of: Void.self) { group in
                for session in sessions {
                    group.addTask { await session.terminate() }
                }
            }
            await stopPTY.value
            await desktopTransport?.stop()
            exit(exitCode)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestShutdown(exitCode: 0)
        return .terminateLater
    }
}
