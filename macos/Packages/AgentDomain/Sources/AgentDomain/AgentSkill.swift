import Foundation

public struct AgentSkill: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name + "\u{0}" + path }
    public let name: String
    public let description: String
    public let path: String
    public let runtimeFingerprint: String?

    public init(name: String, description: String, path: String, runtimeFingerprint: String? = nil) {
        self.name = name
        self.description = description
        self.path = path
        self.runtimeFingerprint = runtimeFingerprint
    }
}

public struct AgentSkillSelection: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let runtimeFingerprint: String?

    public init(name: String, path: String, runtimeFingerprint: String? = nil) {
        self.name = name
        self.path = path
        self.runtimeFingerprint = runtimeFingerprint
    }
}
