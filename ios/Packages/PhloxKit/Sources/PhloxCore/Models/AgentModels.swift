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
