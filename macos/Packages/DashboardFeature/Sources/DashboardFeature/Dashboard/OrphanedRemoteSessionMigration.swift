import AgentDomain

public enum OrphanedRemoteSessionMigration {
    /// モバイル requester を親として書かれた孤児 descriptor を `.remoteUser` ルートへ正規化する。
    /// 対象外の descriptor は一切変更しない。順序・件数を保つ。冪等。
    public nonisolated static func migrate(
        descriptors: [PersistedSessionDescriptor],
        privilegedRequester: SessionID?
    ) -> [PersistedSessionDescriptor] {
        guard let privilegedRequester else { return descriptors }

        let existingSessionIDs = Set(descriptors.map(\.id))
        guard !existingSessionIDs.contains(privilegedRequester) else {
            return descriptors
        }

        return descriptors.map { descriptor in
            guard descriptor.launchContext == .orchestration,
                  descriptor.parentSessionID == privilegedRequester
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
