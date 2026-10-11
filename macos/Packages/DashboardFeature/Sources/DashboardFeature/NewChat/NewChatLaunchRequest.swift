import AgentDomain
import SessionFeature

public struct NewChatLaunchRequest: Sendable {
    public let projectID: ProjectID
    public let agentRef: AgentRef
    public let settings: CodexAppServerSessionSettings
    public let usesWorktree: Bool
    public let text: String
    public let attachments: [ComposerAttachment]
    public let resumeHistoryID: String?

    public init(projectID: ProjectID, agentRef: AgentRef, settings: CodexAppServerSessionSettings,
                usesWorktree: Bool, text: String, attachments: [ComposerAttachment], resumeHistoryID: String? = nil) {
        self.projectID = projectID
        self.agentRef = agentRef
        self.settings = settings
        self.usesWorktree = usesWorktree
        self.text = text
        self.attachments = attachments
        self.resumeHistoryID = resumeHistoryID
    }
}
