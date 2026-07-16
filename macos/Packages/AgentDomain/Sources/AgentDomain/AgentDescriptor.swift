import Foundation

/// DesignSystem に依存せず CLI 識別色を共有するための RGB 生値。
public struct AgentRGB: Sendable, Equatable {
    public let r: Int
    public let g: Int
    public let b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// セッション起動前に CWD へ設置する hook 設定ファイルの種類。
public enum AgentHookKind: Sendable, Equatable {
    case none
    case claudeSettings
    case codexStyle
    case cursorStyle
}

/// 新規/復元起動時に resume ID から追加する引数の宣言。
public enum AgentResumeArgument: Sendable, Equatable {
    /// 既存 args の末尾に `prefix + resumeID` を追加する。
    case append(prefix: [String])
    /// `prefix + resumeID` を既存 args の先頭に追加する。
    case prepend(prefix: [String])
    /// resume ID を使わず固定 args を末尾に追加する。
    case appendStatic([String])
}

/// 新規セッションに永続化する resume ID の決め方。
public enum AgentInitialResumeIDStrategy: Sendable, Equatable {
    case none
    case phloxUUID
    case cursorCreateChat
    case codexNativeFromHook
}

/// Usage サイドバーで使うプロバイダ種別。
public enum AgentUsageProviderKind: Sendable, Equatable {
    case none
    case claudeRateLimits
    case codex
    case cursor
}

/// CLI ごとの起動方法を宣言的に表す spec。
public struct AgentLaunchSpec: Sendable, Equatable {
    public let baseArgs: [String]
    public let bypassArgs: [String]
    public let bypassEnv: [String: String]
    public let hookKind: AgentHookKind
    public let scrollbackPolicy: ScrollbackPolicy
    public let statusBootstrap: StatusBootstrap
    public let postSpawnReset: PostSpawnReset?
    public let debugDump: Bool
    public let newSessionResumeArgument: AgentResumeArgument?
    public let resumeArgument: AgentResumeArgument?
    public let initialResumeIDStrategy: AgentInitialResumeIDStrategy
    public let followsNativeSessionIDFromHook: Bool

    public init(
        baseArgs: [String] = [],
        bypassArgs: [String] = [],
        bypassEnv: [String: String] = [:],
        hookKind: AgentHookKind = .none,
        scrollbackPolicy: ScrollbackPolicy = .keep,
        statusBootstrap: StatusBootstrap = .viaHook,
        postSpawnReset: PostSpawnReset? = nil,
        debugDump: Bool = false,
        newSessionResumeArgument: AgentResumeArgument? = nil,
        resumeArgument: AgentResumeArgument? = nil,
        initialResumeIDStrategy: AgentInitialResumeIDStrategy = .none,
        followsNativeSessionIDFromHook: Bool = false
    ) {
        self.baseArgs = baseArgs
        self.bypassArgs = bypassArgs
        self.bypassEnv = bypassEnv
        self.hookKind = hookKind
        self.scrollbackPolicy = scrollbackPolicy
        self.statusBootstrap = statusBootstrap
        self.postSpawnReset = postSpawnReset
        self.debugDump = debugDump
        self.newSessionResumeArgument = newSessionResumeArgument
        self.resumeArgument = resumeArgument
        self.initialResumeIDStrategy = initialResumeIDStrategy
        self.followsNativeSessionIDFromHook = followsNativeSessionIDFromHook
    }
}

/// AgentKind を識別子だけに保ち、CLI ごとのデータを集約する descriptor。
public struct AgentDescriptor: Sendable, Equatable {
    public let ref: AgentRef
    public let displayName: String
    public let binaryName: String
    public let symbolName: String
    public let colorRGB: AgentRGB
    public let bypassKey: String
    public let usageProviderKind: AgentUsageProviderKind
    public let launchSpec: AgentLaunchSpec
    public let supportsStructuredChat: Bool

    public var kind: AgentKind {
        guard let kind = ref.builtinKind else {
            preconditionFailure("Custom AgentDescriptor has no AgentKind: \(ref.id)")
        }
        return kind
    }

    public init(
        kind: AgentKind,
        displayName: String,
        binaryName: String,
        symbolName: String,
        colorRGB: AgentRGB,
        bypassKey: String,
        usageProviderKind: AgentUsageProviderKind,
        launchSpec: AgentLaunchSpec,
        supportsStructuredChat: Bool = false
    ) {
        self.ref = .builtin(kind)
        self.displayName = displayName
        self.binaryName = binaryName
        self.symbolName = symbolName
        self.colorRGB = colorRGB
        self.bypassKey = bypassKey
        self.usageProviderKind = usageProviderKind
        self.launchSpec = launchSpec
        self.supportsStructuredChat = supportsStructuredChat
    }

    public init(
        ref: AgentRef,
        displayName: String,
        binaryName: String,
        symbolName: String,
        colorRGB: AgentRGB,
        bypassKey: String,
        usageProviderKind: AgentUsageProviderKind = .none,
        launchSpec: AgentLaunchSpec,
        supportsStructuredChat: Bool = false
    ) {
        self.ref = ref
        self.displayName = displayName
        self.binaryName = binaryName
        self.symbolName = symbolName
        self.colorRGB = colorRGB
        self.bypassKey = bypassKey
        self.usageProviderKind = usageProviderKind
        self.launchSpec = launchSpec
        self.supportsStructuredChat = supportsStructuredChat
    }
}

/// 既定 CLI の唯一の宣言的レジストリ。
public enum AgentRegistry {
    public static let descriptors: [AgentKind: AgentDescriptor] = {
        let entries = allDescriptors.map { ($0.kind, $0) }
        return Dictionary(uniqueKeysWithValues: entries)
    }()

    public static let allDescriptors: [AgentDescriptor] = [
        AgentDescriptor(
            kind: .claudeCode,
            displayName: "Claude Code",
            binaryName: "claude",
            symbolName: "sparkles",
            colorRGB: AgentRGB(0xE0, 0xAF, 0x68),
            bypassKey: "phlox.bypass.claudeCode",
            usageProviderKind: .claudeRateLimits,
            launchSpec: AgentLaunchSpec(
                hookKind: .claudeSettings,
                statusBootstrap: .viaHook,
                newSessionResumeArgument: .append(prefix: ["--session-id"]),
                resumeArgument: .append(prefix: ["--resume"]),
                initialResumeIDStrategy: .phloxUUID,
                followsNativeSessionIDFromHook: true
            ),
            supportsStructuredChat: true
        ),
        AgentDescriptor(
            kind: .codex,
            displayName: "Codex",
            binaryName: "codex",
            symbolName: "chevron.left.forwardslash.chevron.right",
            colorRGB: AgentRGB(0x7C, 0x8C, 0xFF),
            bypassKey: "phlox.bypass.codex",
            usageProviderKind: .codex,
            launchSpec: AgentLaunchSpec(
                bypassArgs: ["--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust"],
                hookKind: .codexStyle,
                statusBootstrap: .idleOnSpawnComplete,
                resumeArgument: .prepend(prefix: ["resume"]),
                initialResumeIDStrategy: .codexNativeFromHook
            ),
            supportsStructuredChat: true
        ),
        AgentDescriptor(
            kind: .cursor,
            displayName: "Cursor",
            binaryName: "cursor-agent",
            symbolName: "cursorarrow.rays",
            colorRGB: AgentRGB(0xB9, 0xB3, 0xD0),
            bypassKey: "phlox.bypass.cursor",
            usageProviderKind: .cursor,
            launchSpec: AgentLaunchSpec(
                bypassArgs: ["--force", "--sandbox", "disabled"],
                hookKind: .cursorStyle,
                statusBootstrap: .idleOnSpawnComplete,
                debugDump: false,
                newSessionResumeArgument: .append(prefix: ["--resume"]),
                resumeArgument: .append(prefix: ["--resume"]),
                initialResumeIDStrategy: .cursorCreateChat
            ),
            supportsStructuredChat: true
        ),
    ]

    public static var optionalBinaryKinds: [AgentKind] {
        allDescriptors.map(\.kind).filter { $0 != .claudeCode }
    }

    public static func descriptor(for kind: AgentKind) -> AgentDescriptor {
        guard let descriptor = descriptors[kind] else {
            preconditionFailure("Missing AgentDescriptor for \(kind)")
        }
        return descriptor
    }
}

/// 組込 descriptor に JSON 由来 descriptor を重ねた実行時 catalog。
public struct AgentCatalog: Sendable, Equatable {
    public static let builtins = AgentCatalog(customDescriptors: [])

    public let allDescriptors: [AgentDescriptor]
    private let descriptorsByID: [String: AgentDescriptor]

    public init(customDescriptors: [AgentDescriptor]) {
        let builtins = AgentRegistry.allDescriptors
        var seen = Set(builtins.map { $0.ref.id })
        let custom = customDescriptors.filter { descriptor in
            guard case .custom = descriptor.ref else { return false }
            return seen.insert(descriptor.ref.id).inserted
        }
        self.allDescriptors = builtins + custom
        self.descriptorsByID = Dictionary(uniqueKeysWithValues: allDescriptors.map { ($0.ref.id, $0) })
    }

    public var optionalDescriptors: [AgentDescriptor] {
        allDescriptors.filter { $0.ref != .builtin(.claudeCode) }
    }

    public func descriptor(for ref: AgentRef) -> AgentDescriptor? {
        descriptorsByID[ref.id]
    }
}
