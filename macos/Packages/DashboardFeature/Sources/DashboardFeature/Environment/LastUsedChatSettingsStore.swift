import Foundation

public struct LastUsedChatSettings: Equatable, Sendable {
    public var model: String?
    public var effort: String?
    public var permission: String?
    public var isPlanMode: Bool?

    public init(model: String? = nil, effort: String? = nil, permission: String? = nil, isPlanMode: Bool? = nil) {
        self.model = model
        self.effort = effort
        self.permission = permission
        self.isPlanMode = isPlanMode
    }
}

public struct LastUsedChatSettingsStore {
    private static let keyPrefix = "phlox.lastUsedChatSettings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func record(agentID: String, model: String?, effort: String?, permission: String? = nil, isPlanMode: Bool? = nil) {
        let base = "\(Self.keyPrefix).\(agentID)"
        defaults.set(permission, forKey: "\(base).permission")
        defaults.set(isPlanMode, forKey: "\(base).planMode")
        if let model {
            defaults.set(model, forKey: "\(base).model")
        } else {
            defaults.removeObject(forKey: "\(base).model")
        }
        if let effort {
            defaults.set(effort, forKey: "\(base).effort")
        } else {
            defaults.removeObject(forKey: "\(base).effort")
        }
    }

    public func lastUsed(agentID: String) -> LastUsedChatSettings? {
        let base = "\(Self.keyPrefix).\(agentID)"
        let model = defaults.string(forKey: "\(base).model")
        let effort = defaults.string(forKey: "\(base).effort")
        let permission = defaults.string(forKey: "\(base).permission")
        let isPlanMode = defaults.object(forKey: "\(base).planMode") as? Bool
        guard model != nil || effort != nil || permission != nil || isPlanMode != nil else { return nil }
        return LastUsedChatSettings(model: model, effort: effort, permission: permission, isPlanMode: isPlanMode)
    }

    public var lastHarness: String? { defaults.string(forKey: "phlox.newChat.lastHarness") }

    public func recordLastHarness(_ agentID: String) {
        defaults.set(agentID, forKey: "phlox.newChat.lastHarness")
    }
}
