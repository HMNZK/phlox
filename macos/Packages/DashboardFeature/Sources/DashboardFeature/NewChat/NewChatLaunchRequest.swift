import AgentDomain
import SessionFeature

public struct NewChatLaunchRequest: Sendable {
    public let projectID: ProjectID
    public let agentRef: AgentRef
    public let settings: CodexAppServerSessionSettings
    public let usesWorktree: Bool
    public let worktreeStartPoint: WorktreeStartPoint
    public let text: String
    public let attachments: [ComposerAttachment]
    public let workingDirectoryOverride: String?
    public let resumeHistoryID: String?

    public init(projectID: ProjectID, agentRef: AgentRef, settings: CodexAppServerSessionSettings,
                usesWorktree: Bool, text: String, attachments: [ComposerAttachment],
                workingDirectoryOverride: String? = nil, resumeHistoryID: String? = nil,
                worktreeStartPoint: WorktreeStartPoint = .head) {
        self.projectID = projectID
        self.agentRef = agentRef
        self.settings = settings
        self.usesWorktree = usesWorktree
        self.worktreeStartPoint = worktreeStartPoint
        self.text = text
        self.attachments = attachments
        self.workingDirectoryOverride = workingDirectoryOverride
        self.resumeHistoryID = resumeHistoryID
    }
}
