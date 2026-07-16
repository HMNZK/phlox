import Testing
@testable import Features

/// wave-4 task-2: Projects 一覧の静的契約（タイトル・FAB 撤去・subtitle 撤去・プロジェクト別追加行）。
@Suite struct Wave4ProjectsListWhiteboxTests {
    @Test func projectsListStaticContract() {
        #expect(SessionListView.listTitle == "Projects")
        #expect(SessionListView.providesPerProjectAddSessionRow)
        #expect(!SessionListView.providesSpawnFAB)
        #expect(!SessionListView.providesListSubtitle)
    }
}
