import Foundation
import Testing
import PhloxCore
@testable import Features

/// グルーピングキー（`projectId` 優先）の固定仕様を白箱で検証する。
struct Wave2SessionGroupingWhiteboxTests {
    private func makeSession(
        id: String,
        projectId: String? = nil,
        projectName: String? = nil
    ) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            projectId: projectId,
            projectName: projectName,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

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
