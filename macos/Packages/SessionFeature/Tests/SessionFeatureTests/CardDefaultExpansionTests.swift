import Testing
@testable import SessionFeature

// 04「カードの既定の開き方」: コマンド単体は失敗したものだけ開く（C-22）、タスクリストは最新だけ開く（C-16）。
@Suite("Card default expansion")
struct CardDefaultExpansionTests {
    @Test
    func singleCommandOpensOnlyWhenFailed() {
        let succeeded = TranscriptItemPresentation.command(path: .single, itemCount: 1, isRunning: false, hasNonBlankOutput: true)
        let failed = TranscriptItemPresentation.command(path: .single, itemCount: 1, isRunning: false, hasNonBlankOutput: true, hasFailed: true)
        let running = TranscriptItemPresentation.command(path: .single, itemCount: 1, isRunning: true, hasNonBlankOutput: false)
        #expect(!succeeded.defaultExpanded)
        #expect(failed.defaultExpanded)
        #expect(running.defaultExpanded)
    }

    @Test
    func commandGroupStaysClosedEvenWhenFailed() {
        let failedGroup = TranscriptItemPresentation.command(path: .group, itemCount: 3, isRunning: false, hasNonBlankOutput: true, hasFailed: true)
        #expect(!failedGroup.defaultExpanded)
    }

    @Test
    func failureIsReadFromTheExitCodeLine() {
        #expect(CommandExitCode.parse("Exit code 1\nerror: build failed") == 1)
        #expect(CommandExitCode.parse("Exit code 0\nok") == 0)
        #expect(CommandExitCode.parse("ok") == nil)
    }

    @Test
    func onlyTheLatestTaskListOpens() {
        #expect(TranscriptItemPresentation.taskList(count: 2, isLatest: true).defaultExpanded)
        #expect(!TranscriptItemPresentation.taskList(count: 2, isLatest: false).defaultExpanded)
    }
}

