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

    @Test("グループから作る追加セッション下書きは表示名と本物の projectID を使う")
    func addSessionDraftUsesProjectGroupContext() {
        let groups = SessionGrouping.grouped(from: [
            makeSession(id: "id", projectID: "project-id", projectName: "ID を持つプロジェクト"),
            makeSession(id: "name", projectID: nil, projectName: "名前だけのプロジェクト"),
            makeSession(id: "other", projectID: nil, projectName: nil),
        ])

        #expect(groups.map(\.addSessionDraft) == [
            SessionComposeDraft(project: "ID を持つプロジェクト", projectID: "project-id"),
            SessionComposeDraft(project: "名前だけのプロジェクト", projectID: nil),
            SessionComposeDraft(project: "その他", projectID: nil),
        ])
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
