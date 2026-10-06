import Foundation
import Testing
import PhloxCore
@testable import Features

/// セッション一覧のプロジェクト単位グルーピング（純ロジック）。
/// グループの `.id` の値は実装依存のため検証しない。`.title` と `.sessions` の順序を検証する。
@Suite("Session grouping") struct SessionGroupingTests {
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

    // グルーピングキーは projectId 優先。同じ projectId なら projectName が違っても 1 グループ。
    @Test func groupsByProjectIdWhenBothIdAndNamePresent() {
        let sessions = [
            makeSession(id: "s1", projectId: "p-1", projectName: "Alpha"),
            makeSession(id: "s2", projectId: "p-2", projectName: "Beta"),
            makeSession(id: "s3", projectId: "p-1", projectName: "Alpha Renamed"),
        ]

        let result = SessionGrouping.grouped(from: sessions)

        #expect(result.count == 2)
        #expect(result[0].sessions.map(\.id) == ["s1", "s3"])
        #expect(result[0].title == "Alpha")
        #expect(result[1].sessions.map(\.id) == ["s2"])
    }

    @Test func fallsBackToProjectNameWhenProjectIdMissing() {
        let sessions = [
            makeSession(id: "s1", projectId: nil, projectName: "Solo"),
            makeSession(id: "s2", projectId: nil, projectName: "Solo"),
        ]

        let result = SessionGrouping.grouped(from: sessions)

        #expect(result.count == 1)
        #expect(result[0].title == "Solo")
        #expect(result[0].sessions.map(\.id) == ["s1", "s2"])
    }
}
