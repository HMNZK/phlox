import AgentDomain

public enum AgentModelCatalog {
    private static let claudeModels = [
        ControlModelOption(id: "opus", displayName: "Opus 4.8"),
        ControlModelOption(id: "sonnet", displayName: "Sonnet 5"),
        ControlModelOption(id: "fable", displayName: "Fable 5"),
        ControlModelOption(id: "haiku", displayName: "Haiku 4.5"),
    ]

    private static let cursorModels = ["gpt-5", "sonnet-4.5", "opus-4.1"].map {
        ControlModelOption(id: $0, displayName: $0)
    }

    public static func models(for kind: AgentKind) -> [ControlModelOption] {
        switch kind {
        case .claudeCode:
            claudeModels
        case .codex:
            []
        case .cursor:
            cursorModels
        }
    }

    public static func defaultModel(for kind: AgentKind) -> String? {
        switch kind {
        case .claudeCode:
            "sonnet"
        case .codex:
            nil
        case .cursor:
            cursorModels.first?.id
        }
    }
}
