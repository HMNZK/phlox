import AgentDomain
import AppBootstrap
import AppKit
import ClaudeAgentKit
import DashboardFeature
import Darwin
import Foundation
import PTYKit
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
                }, command: { command in
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
                }, applicationCommand: { data in
                    let command = try JSONDecoder().decode(SessionRuntimeApplicationCommand.self, from: data)
                    let reply: SessionRuntimeApplicationReply
                    switch command {
                    case .mobile(let command): reply = .mobile(try await root.mobileTokenViewModel.performRuntimeCommand(command))
                    case .preferences(let values):
                        try SessionRuntimePreferences.apply(values)
                        root.usage.usageSettingsChanged()
                        reply = .preferencesApplied
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
