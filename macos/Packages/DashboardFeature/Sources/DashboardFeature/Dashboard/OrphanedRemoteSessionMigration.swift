import AgentDomain

public enum OrphanedRemoteSessionMigration {
    /// モバイル requester を親として書かれた孤児 descriptor を `.remoteUser` ルートへ正規化する。
    /// 対象外の descriptor は一切変更しない。順序・件数を保つ。冪等。
    public nonisolated static func migrate(
        descriptors: [PersistedSessionDescriptor],
        privilegedRequesters: Set<SessionID>
    ) -> [PersistedSessionDescriptor] {
        guard !privilegedRequesters.isEmpty else { return descriptors }

        let existingSessionIDs = Set(descriptors.map(\.id))

        return descriptors.map { descriptor in
            guard descriptor.launchContext == .orchestration,
                  let parentSessionID = descriptor.parentSessionID,
                  privilegedRequesters.contains(parentSessionID),
                  !existingSessionIDs.contains(parentSessionID)
            else {
                return descriptor
            }
            return descriptor.updating(
                launchContext: .remoteUser,
                parentSessionID: nil
            )
        }
    }
}
