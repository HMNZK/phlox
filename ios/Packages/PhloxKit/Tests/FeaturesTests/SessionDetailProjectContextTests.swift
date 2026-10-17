import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
struct SessionDetailProjectContextTests {
    @Test("セッション詳細はサーバー由来の projectName を表示する")
    func sessionContextUsesServerProjectName() {
        let session = Session(
            id: "s1",
            name: "Task",
            agent: .claudeCode,
            status: .idle,
            subtitle: "workspace-path",
            projectId: "project-uuid",
            projectName: "Gardenia",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let viewModel = SessionDetailViewModel(session: session, api: MockAPI())

        #expect(viewModel.inputContextDisplayName == "Gardenia")
    }
}
