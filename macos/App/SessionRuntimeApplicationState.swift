import AgentDomain
import AppBootstrap
import DashboardFeature
import Foundation

struct SessionRuntimeApplicationSnapshot: Codable, Sendable {
    let pathEnvironment: String
    let claudeBinaryPath: String
    let hookDispatcherPath: String
    let mobile: MobileRuntimeSnapshot
    let models: [AgentKind: [ControlModelOption]]
}

struct SessionRuntimeModelProvider: AgentModelListProviding {
    let models: [AgentKind: [ControlModelOption]]

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        guard let result = models[kind] else {
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }
        return result
    }
}

enum SessionRuntimeApplicationCommand: Codable, Sendable {
    case mobile(MobileRuntimeCommand)
    case preferences([String: SessionRuntimePreference])
    /// 実行サービスを、`bundlePath`の新版へ実行を止めずに切り替える（ADR 0233）。
    case handover(bundlePath: String)
}

enum SessionRuntimeApplicationReply: Codable, Sendable {
    case mobile(MobileRuntimeReply)
    case preferencesApplied
    /// 切り替えを始めた。画面側は新しい実行サービスへ再接続する。
    case handoverStarted
    /// 更新を延期した（未対応の実行が動いている等）。実行中のものには何もしていない。
    case handoverDeferred([String])
}

enum SessionRuntimePreference: Codable, Equatable, Sendable {
    case boolean(Bool)
    case text(String)
}

@MainActor
enum SessionRuntimePreferences {
    static var keys: Set<String> {
        Set([BypassSettings.defaultsDictionary, NotificationSettings.defaultsDictionary,
             UsageSettings.defaultsDictionary, CodexUserHooksSettings.defaultsDictionary]
            .flatMap(\.keys))
    }

    static func snapshot() -> [String: SessionRuntimePreference] {
        let defaults = UserDefaults.phloxDefaults()
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            guard let value = defaults.object(forKey: key) else { return nil }
            if let string = value as? String { return (key, .text(string)) }
            if let number = value as? NSNumber { return (key, .boolean(number.boolValue)) }
            return nil
        })
    }

    static func apply(_ values: [String: SessionRuntimePreference]) throws {
        guard values.keys.allSatisfy(keys.contains) else {
            throw SessionRuntimeConnectionError.rejected("同期できない設定が含まれています。")
        }
        let defaults = UserDefaults.phloxDefaults()
        for (key, value) in values {
            switch value {
            case .boolean(let value): defaults.set(value, forKey: key)
            case .text(let value): defaults.set(value, forKey: key)
            }
        }
    }
}
