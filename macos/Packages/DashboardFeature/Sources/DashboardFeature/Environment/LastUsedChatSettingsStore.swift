import Foundation

public struct LastUsedChatSettings: Equatable, Sendable {
    public var model: String?
    public var effort: String?

    public init(model: String? = nil, effort: String? = nil) {
        self.model = model
        self.effort = effort
    }
}

public struct LastUsedChatSettingsStore {
    private static let keyPrefix = "phlox.lastUsedChatSettings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func record(agentID: String, model: String?, effort: String?) {
        let base = "\(Self.keyPrefix).\(agentID)"
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
        guard model != nil || effort != nil else { return nil }
        return LastUsedChatSettings(model: model, effort: effort)
    }
}
