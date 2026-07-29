import Foundation
import Testing
import PhloxCore
import Features

@Suite("ProjectGroup の送信用 projectID")
struct SessionGroupingProjectIDWhiteboxTests {
    @Test("本物の session.projectId を持つグループだけ projectID を持つ")
    func projectIDIsOnlySetForRealProjectIDs() {
        let result = SessionGrouping.grouped(from: [
            makeSession(id: "id", projectID: "project-id", projectName: "ID を持つプロジェクト"),
            makeSession(id: "name", projectID: nil, projectName: "名前だけのプロジェクト"),
            makeSession(id: "other", projectID: nil, projectName: nil),
        ])

        #expect(result.map(\.projectID) == ["project-id", nil, nil])
    }

    private func makeSession(id: String, projectID: String?, projectName: String?) -> Session {
        Session(
            id: id,
            name: id,
            agent: .codex,
            status: .idle,
            subtitle: "",
            projectId: projectID,
            projectName: projectName,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
