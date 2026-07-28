import AgentDomain

public struct SessionOrigin: Sendable, Equatable {
    public let launchContext: SessionLaunchContext
    public let parentSessionID: SessionID?

    public init(
        launchContext: SessionLaunchContext,
        parentSessionID: SessionID?
    ) {
        self.launchContext = launchContext
        self.parentSessionID = parentSessionID
    }
}

public enum SessionOriginPolicy {
    public nonisolated static func origin(
        requester: SessionID?,
        requesterIsExistingSession: Bool
    ) -> SessionOrigin {
        guard requesterIsExistingSession, let requester else {
            return SessionOrigin(
                launchContext: .remoteUser,
                parentSessionID: nil
            )
        }
        return SessionOrigin(
            launchContext: .orchestration,
            parentSessionID: requester
        )
    }
}
