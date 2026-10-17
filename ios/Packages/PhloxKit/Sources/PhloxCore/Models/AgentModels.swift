public struct SessionModelOption: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct AgentModels: Sendable, Equatable, Decodable {
    public let models: [SessionModelOption]
    public let defaultModel: String?

    public init(models: [SessionModelOption], defaultModel: String?) {
        self.models = models
        self.defaultModel = defaultModel
    }
}

/// A setting value and the display name supplied by the Mac. `nil` means the agent's default.
public struct AgentSettingOption: Sendable, Equatable, Decodable {
    public let value: String?
    public let displayName: String

    public init(value: String?, displayName: String) {
        self.value = value
        self.displayName = displayName
    }
}

/// Settings supported when starting a session for an agent.
public struct AgentSettings: Sendable, Equatable, Decodable {
    public let availableEfforts: [String: [AgentSettingOption]]
    public let availablePermissions: [AgentSettingOption]
    public let planModeAvailable: Bool
    public let defaultEfforts: [String: String]?
    public let defaultPermission: String?

    public init(
        availableEfforts: [String: [AgentSettingOption]],
        availablePermissions: [AgentSettingOption],
        planModeAvailable: Bool,
        defaultEfforts: [String: String]? = nil,
        defaultPermission: String? = nil
    ) {
        self.availableEfforts = availableEfforts
        self.availablePermissions = availablePermissions
        self.planModeAvailable = planModeAvailable
        self.defaultEfforts = defaultEfforts
        self.defaultPermission = defaultPermission
    }
}

/// One Mac project returned by `GET /projects`.
public struct ProjectSummary: Sendable, Equatable, Identifiable, Decodable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
