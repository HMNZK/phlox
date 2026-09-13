import SessionFeature

extension ComposerDestinationLabel {
    static func teamDestination(
        action: AgoraComposerAction,
        rootProjectName: String?,
        rootTaskName: String?
    ) -> Destination {
        switch action {
        case .startDiscussion: return .startDiscussion
        case .discussionUtterance: return .discussionUtterance
        case .legacyRootSend: return .parentSession(projectName: rootProjectName, taskName: rootTaskName)
        }
    }
}
