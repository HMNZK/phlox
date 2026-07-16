import Foundation
import AgentDomain

/// AgentLaunchPlanner が生成する起動計画。SpawnRequest 構築に必要な情報と、
/// scrollback ポリシー・状態遷移モードをまとめて持つ。
public struct AgentLaunchPlan: Sendable {
    public let command: String
    public let args: [String]
    public let env: [String: String]
    public let workingDirectory: String?
    public let ref: AgentRef
    public let descriptor: AgentDescriptor
    public let scrollbackPolicy: ScrollbackPolicy
    public let statusBootstrap: StatusBootstrap
    public let postSpawnReset: PostSpawnReset?
    public let debugDump: Bool

    public var kind: AgentKind {
        guard let kind = ref.builtinKind else {
            preconditionFailure("Custom AgentLaunchPlan has no AgentKind: \(ref.id)")
        }
        return kind
    }
}

public enum AgentLaunchPlannerError: Error {
    case binaryNotFound(AgentKind)
    case customBinaryNotFound(String)
    case unknownAgent(AgentRef)
}

public enum AgentLaunchMode: Sendable, Equatable {
    case newSession(resumeID: String? = nil)
    case resume(resumeID: String)
}

public struct AgentLaunchPlanner: Sendable {
    public init() {}

    /// AgentKind と AppEnvironment、SessionID から AgentLaunchPlan を生成する。
    public func plan(
        kind: AgentKind,
        environment: AppEnvironment,
        sessionID: SessionID,
        sessionToken: String,
        workingDirectoryOverride: String? = nil,
        launchMode: AgentLaunchMode = .newSession(),
        backend: SessionBackend = .pty,
        bypassEnabled: Bool = true,
        codexUserHooksEnabled: Bool = false,
        extraEnv: [String: String] = [:]
    ) throws -> AgentLaunchPlan {
        try plan(
            ref: .builtin(kind),
            environment: environment,
            sessionID: sessionID,
            sessionToken: sessionToken,
            workingDirectoryOverride: workingDirectoryOverride,
            launchMode: launchMode,
            backend: backend,
            bypassEnabled: bypassEnabled,
            codexUserHooksEnabled: codexUserHooksEnabled,
            extraEnv: extraEnv
        )
    }

    /// AgentRef と AppEnvironment、SessionID から AgentLaunchPlan を生成する。
    public func plan(
        ref: AgentRef,
        environment: AppEnvironment,
        sessionID: SessionID,
        sessionToken: String,
        workingDirectoryOverride: String? = nil,
        launchMode: AgentLaunchMode = .newSession(),
        backend: SessionBackend = .pty,
        bypassEnabled: Bool = true,
        codexUserHooksEnabled: Bool = false,
        extraEnv: [String: String] = [:]
    ) throws -> AgentLaunchPlan {
        guard let descriptor = environment.agentCatalog.descriptor(for: ref) else {
            throw AgentLaunchPlannerError.unknownAgent(ref)
        }
        guard let command = environment.binaryPath(for: ref) else {
            if let kind = ref.builtinKind {
                throw AgentLaunchPlannerError.binaryNotFound(kind)
            }
            throw AgentLaunchPlannerError.customBinaryNotFound(ref.id)
        }

        let profile = profile(
            for: descriptor,
            environment: environment,
            backend: backend,
            bypassEnabled: bypassEnabled,
            codexUserHooksEnabled: codexUserHooksEnabled
        )

        // 不要な TCC 権限要求を避けるため login shell (`/bin/zsh -l`) は経由せず、
        // 最小限の環境変数のみを子プロセスに引き継ぐ。
        var env: [String: String] = [
            "PATH": environment.pathEnvironment,
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8",
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "PHLOX_SESSION_ID": sessionID.rawValue.uuidString,
        ]
        env["PHLOX_API_URL"] = environment.controlURL.absoluteString
        env["PHLOX_TOKEN"] = sessionToken
        env["PHLOX_CLI"] = environment.cliPath
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            env["SHELL"] = shell
        }
        for (key, value) in profile.extraEnv {
            env[key] = value
        }

        let workingDirectory = workingDirectoryOverride
            ?? environment.sessionWorkspaceDirectory(for: sessionID).path

        var args = profile.extraArgs
        switch profile.hookIntegration {
        case .claudeSettings(let settingsPath, let hookURL):
            args = ["--settings", settingsPath]
            env["CLAUDE_HOOKS_URL"] = hookURL.absoluteString
        case .codexHooks(let hookURL):
            env["CLAUDE_HOOKS_URL"] = hookURL.absoluteString
        case .cursorHooks(let hookURL):
            env["CLAUDE_HOOKS_URL"] = hookURL.absoluteString
        case .none:
            break
        }
        args = Self.applyLaunchMode(launchMode, to: args, using: profile)
        for (key, value) in extraEnv where env[key] == nil {
            env[key] = value
        }

        let effectiveDump = profile.debugDump || Self.globalDebugDumpOverride
        return AgentLaunchPlan(
            command: command,
            args: args,
            env: env,
            workingDirectory: workingDirectory,
            ref: ref,
            descriptor: descriptor,
            scrollbackPolicy: profile.scrollbackPolicy,
            statusBootstrap: profile.statusBootstrap,
            postSpawnReset: profile.postSpawnReset,
            debugDump: effectiveDump
        )
    }

    private static func applyLaunchMode(
        _ launchMode: AgentLaunchMode,
        to baseArgs: [String],
        using profile: AgentLaunchProfile
    ) -> [String] {
        switch launchMode {
        case .newSession(let resumeID):
            guard let resumeID, let argument = profile.newSessionResumeArgument else { return baseArgs }
            return Self.applyResumeArgument(argument, resumeID: resumeID, to: baseArgs)
        case .resume(let resumeID):
            guard let argument = profile.resumeArgument else { return baseArgs }
            return Self.applyResumeArgument(argument, resumeID: resumeID, to: baseArgs)
        }
    }

    private static func applyResumeArgument(
        _ argument: AgentResumeArgument,
        resumeID: String,
        to baseArgs: [String]
    ) -> [String] {
        switch argument {
        case .append(let prefix):
            return baseArgs + prefix + [resumeID]
        case .prepend(let prefix):
            return prefix + [resumeID] + baseArgs
        case .appendStatic(let args):
            return baseArgs + args
        }
    }

    private static var globalDebugDumpOverride: Bool {
        ProcessInfo.processInfo.environment["PHLOX_DEBUG_DUMP"] == "1"
    }

    private func profile(
        for descriptor: AgentDescriptor,
        environment: AppEnvironment,
        backend: SessionBackend,
        bypassEnabled: Bool,
        codexUserHooksEnabled: Bool
    ) -> AgentLaunchProfile {
        let spec = descriptor.launchSpec
        if backend == .appServer {
            return AgentLaunchProfile(
                extraArgs: spec.baseArgs,
                extraEnv: [:],
                hookIntegration: .none,
                scrollbackPolicy: spec.scrollbackPolicy,
                statusBootstrap: spec.statusBootstrap,
                postSpawnReset: spec.postSpawnReset,
                debugDump: spec.debugDump,
                newSessionResumeArgument: spec.newSessionResumeArgument,
                resumeArgument: spec.resumeArgument
            )
        }
        let bypassArgs = spec.bypassArgs.filter { arg in
            !(codexUserHooksEnabled && descriptor.ref == .builtin(.codex) && arg == "--dangerously-bypass-hook-trust")
        }
        return AgentLaunchProfile(
            extraArgs: spec.baseArgs + (bypassEnabled ? bypassArgs : []),
            extraEnv: bypassEnabled ? spec.bypassEnv : [:],
            hookIntegration: hookIntegration(for: spec.hookKind, environment: environment, bypassEnabled: bypassEnabled),
            scrollbackPolicy: spec.scrollbackPolicy,
            statusBootstrap: spec.statusBootstrap,
            postSpawnReset: spec.postSpawnReset,
            debugDump: spec.debugDump,
            newSessionResumeArgument: spec.newSessionResumeArgument,
            resumeArgument: spec.resumeArgument
        )
    }

    private func hookIntegration(
        for hookKind: AgentHookKind,
        environment: AppEnvironment,
        bypassEnabled: Bool
    ) -> HookIntegration {
        switch hookKind {
        case .claudeSettings:
            return .claudeSettings(
                settingsPath: (
                    bypassEnabled
                        ? environment.claudeSettingsURL
                        : environment.claudeSettingsRestrictedURL
                ).path,
                hookURL: environment.hookURL
            )
        case .codexStyle:
            return .codexHooks(hookURL: environment.hookURL)
        case .cursorStyle:
            return .cursorHooks(hookURL: environment.hookURL)
        case .none:
            return .none
        }
    }
}
