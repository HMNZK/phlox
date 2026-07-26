import Foundation
import AgentDomain
import CodexAppServerKit

enum CursorModelListProvider {
    static func persistedSettings(from lastUsed: LastUsedChatSettings?) -> CodexAppServerSessionSettings? {
        guard let lastUsed else { return nil }
        return CodexAppServerSessionSettings(
            selectedModel: lastUsed.model,
            selectedEffort: lastUsed.effort,
            selectedPermissionProfile: nil,
            isPlanMode: false
        )
    }

}

extension DashboardViewModel {
    static func persistedSettings(from lastUsed: LastUsedChatSettings?) -> CodexAppServerSessionSettings? {
        CursorModelListProvider.persistedSettings(from: lastUsed)
    }
}
