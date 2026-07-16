// PM著・凍結。アサーション変更禁止。
// このテストファイル自体（ハーネス）に欠陥が見つかった場合のみ、PM 承認のうえで修理可。
//
// task-4: セッション一覧のプロジェクト単位グルーピング。
// 対象仕様: tasks/task-4.md
// 公開API契約（実装役が Features/SessionList/ 配下に作る純ロジック。View非依存）:
//   - ProjectGroup: Identifiable な値型。`title: String`（表示名）と `sessions: [Session]` を持つ。
//   - SessionGrouping.otherGroupTitle: String — projectName=nil セッションの既定グループ表示名。
//   - SessionGrouping.grouped(from sessions: [Session]) -> [ProjectGroup] — 純関数。
//
// グルーピングキー（projectId優先 か projectName優先か）は白箱テスト側で固定してよい。
// 本凍結テストは「同一プロジェクト（projectId・projectName とも一致）が1グループにまとまる」
// ことだけを検証し、キー選択の違いを問わない（tasks/task-4.md 受け入れテスト要件に準拠）。
// グループの `.id` の値も実装依存のため検証しない。`.title` と `.sessions` の順序のみを検証する。

import Foundation
import Testing
import PhloxCore
@testable import Features

struct Wave2SessionGroupingAcceptanceTests {
    private func makeSession(
        id: String,
        projectId: String? = nil,
        projectName: String? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            projectId: projectId,
            projectName: projectName,
            updatedAt: updatedAt
        )
    }

    @Test func groupsSessionsByProjectPreservingOrder() {
        let sessions = [
            makeSession(id: "s1", projectId: "p-a", projectName: "Project A"),
            makeSession(id: "s2", projectId: "p-b", projectName: "Project B"),
            makeSession(id: "s4", projectId: nil, projectName: nil),
            makeSession(id: "s3", projectId: "p-a", projectName: "Project A"),
            makeSession(id: "s5", projectId: "p-b", projectName: "Project B"),
        ]

        let result = SessionGrouping.grouped(from: sessions)

        #expect(result.map(\.title) == ["Project A", "Project B", SessionGrouping.otherGroupTitle])
        #expect(result.map { $0.sessions.map(\.id) } == [["s1", "s3"], ["s2", "s5"], ["s4"]])
    }

    @Test func unassignedSessionsGoToTrailingDefaultGroup() {
        let sessions = [
            makeSession(id: "s1", projectId: nil, projectName: nil),
            makeSession(id: "s2", projectId: "p-c", projectName: "Project C"),
            makeSession(id: "s3", projectId: nil, projectName: nil),
        ]

        let result = SessionGrouping.grouped(from: sessions)

        #expect(result.count == 2)
        #expect(result[0].title == "Project C")
        #expect(result[0].sessions.map(\.id) == ["s2"])
        #expect(result[1].title == SessionGrouping.otherGroupTitle)
        #expect(result[1].sessions.map(\.id) == ["s1", "s3"])
    }

    @Test func sameProjectConsolidatesIntoOneGroup() {
        let sessions = [
            makeSession(id: "s1", projectId: "p-x", projectName: "Project X"),
            makeSession(id: "s2", projectId: "p-y", projectName: "Project Y"),
            makeSession(id: "s3", projectId: "p-x", projectName: "Project X"),
            makeSession(id: "s4", projectId: "p-x", projectName: "Project X"),
        ]

        let result = SessionGrouping.grouped(from: sessions)

        #expect(result.count == 2)
        #expect(result[0].title == "Project X")
        #expect(result[0].sessions.map(\.id) == ["s1", "s3", "s4"])
        #expect(result[1].title == "Project Y")
        #expect(result[1].sessions.map(\.id) == ["s2"])
    }
}
