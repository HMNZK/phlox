import AgentDomain

public enum SessionDisplayStatus {
    public static func resolve(rawStatus: SessionStatus, isProcessing: Bool) -> SessionStatus {
        rawStatus == .idle && isProcessing ? .running : rawStatus
    }
}
