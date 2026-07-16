import Foundation
import AgentDomain

/// `SessionHookInstaller.install` の戻り値。DashboardViewModel が参照し、
/// `.skippedExistingUserFile` のとき UI で「既存設定があるため連携が制限される」旨を警告する。
public enum HookInstallOutcome: Sendable, Equatable {
    case installed
    case skippedExistingUserFile
}

/// 同一 CWD × エージェント種別での hooks 参照カウントキー（`standardizedFileURL.path`）。
private struct HookRefKey: Hashable {
    let cwdPath: String
    let kind: AgentKind
}

@MainActor
final class SessionHookInstaller {
    private let dispatcherPath: String
    private let logError: (Error, String) -> Void

    /// 実ファイルを設置した (cwd, kind) の参照数。`.skippedExistingUserFile` は含めない。
    private var refCounts: [HookRefKey: Int] = [:]
    /// 参照カウント 0 になったとき `HookFileInstaller.cleanup` に渡す設置情報。
    private var installationsByKey: [HookRefKey: HookInstallation] = [:]
    /// 同一キーで 2 本目以降の `install` が返す結果（初回 install と同じ扱い）。
    private var outcomesByKey: [HookRefKey: HookInstallOutcome] = [:]
    /// セッションが参加している参照カウントキー。
    private var sessionBindings: [SessionID: HookRefKey] = [:]

    init(
        dispatcherPath: String,
        logError: @escaping (Error, String) -> Void
    ) {
        self.dispatcherPath = dispatcherPath
        self.logError = logError
    }

    @discardableResult
    func install(kind: AgentKind, sessionID: SessionID, workingDirectory: URL) throws -> HookInstallOutcome {
        try install(
            descriptor: AgentRegistry.descriptor(for: kind),
            sessionID: sessionID,
            workingDirectory: workingDirectory
        )
    }

    @discardableResult
    func install(
        descriptor: AgentDescriptor,
        sessionID: SessionID,
        workingDirectory: URL
    ) throws -> HookInstallOutcome {
        switch descriptor.launchSpec.hookKind {
        case .codexStyle, .cursorStyle:
            guard let kind = descriptor.ref.builtinKind else {
                return .installed
            }
            if sessionBindings[sessionID] != nil {
                releaseBinding(for: sessionID)
            }

            let key = HookRefKey(cwdPath: Self.normalizedCWDPath(workingDirectory), kind: kind)

            if let count = refCounts[key], count > 0 {
                refCounts[key] = count + 1
                sessionBindings[sessionID] = key
                return outcomesByKey[key] ?? .installed
            }

            let outcome = try performFileInstall(
                kind: kind,
                workingDirectory: workingDirectory
            )

            switch outcome {
            case .installed:
                refCounts[key] = 1
                outcomesByKey[key] = .installed
                sessionBindings[sessionID] = key
                return .installed
            case .skippedExistingUserFile:
                // ファイル未設置のため参照カウント・session 紐付けは行わない。
                return .skippedExistingUserFile
            }
        case .claudeSettings, .none:
            return .installed
        }
    }

    func cleanup(for sessionID: SessionID) {
        releaseBinding(for: sessionID)
    }

    @discardableResult
    func reinstall(kind: AgentKind, sessionID: SessionID, workingDirectory: URL) throws -> HookInstallOutcome {
        releaseBinding(for: sessionID)
        return try install(kind: kind, sessionID: sessionID, workingDirectory: workingDirectory)
    }

    @discardableResult
    func reinstall(
        descriptor: AgentDescriptor,
        sessionID: SessionID,
        workingDirectory: URL
    ) throws -> HookInstallOutcome {
        releaseBinding(for: sessionID)
        return try install(descriptor: descriptor, sessionID: sessionID, workingDirectory: workingDirectory)
    }

    // MARK: - 参照カウント

    private func releaseBinding(for sessionID: SessionID) {
        guard let key = sessionBindings.removeValue(forKey: sessionID) else { return }
        guard let count = refCounts[key], count > 0 else { return }

        let next = count - 1
        if next > 0 {
            refCounts[key] = next
            return
        }

        refCounts.removeValue(forKey: key)
        outcomesByKey.removeValue(forKey: key)

        guard let installation = installationsByKey.removeValue(forKey: key) else { return }
        do {
            try HookFileInstaller.cleanup(installation)
        } catch {
            logError(error, "Failed to cleanup hooks for \(sessionID)")
        }
    }

    private static func normalizedCWDPath(_ workingDirectory: URL) -> String {
        workingDirectory.standardizedFileURL.path
    }

    // MARK: - 実ファイル設置（初回のみ）

    @discardableResult
    private func performFileInstall(
        kind: AgentKind,
        workingDirectory: URL
    ) throws -> HookInstallOutcome {
        let key = HookRefKey(cwdPath: Self.normalizedCWDPath(workingDirectory), kind: kind)

        switch AgentRegistry.descriptor(for: kind).launchSpec.hookKind {
        case .codexStyle:
            switch try CodexHooksManager.install(
                workingDirectory: workingDirectory,
                dispatcherPath: dispatcherPath
            ) {
            case .installed(let installation):
                installationsByKey[key] = installation
                return .installed
            case .skippedExistingUserFile:
                return .skippedExistingUserFile
            }
        case .cursorStyle:
            switch try CursorHooksManager.install(
                workingDirectory: workingDirectory,
                dispatcherPath: dispatcherPath
            ) {
            case .installed(let installation):
                installationsByKey[key] = installation
                return .installed
            case .skippedExistingUserFile:
                return .skippedExistingUserFile
            }
        case .claudeSettings, .none:
            return .installed
        }
    }
}
