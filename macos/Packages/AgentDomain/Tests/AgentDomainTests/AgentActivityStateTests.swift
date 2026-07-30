import Foundation
import Testing
@testable import AgentDomain

@Suite("活動状態の分類")
struct AgentActivityClassifierTests {
    @Test(
        "読み取り系ツール名は searching",
        arguments: ["Read /tmp/a.swift", "Grep pattern src", "Glob **/*.swift", "WebSearch swift 6", "rg todo"]
    )
    func readToolsAreSearching(command: String) {
        #expect(AgentActivityClassifier.state(forCommand: command) == .searching)
    }

    @Test(
        "実行系は running",
        arguments: ["swift build", "npm test", "/usr/bin/make all", "Task explore"]
    )
    func executionIsRunning(command: String) {
        #expect(AgentActivityClassifier.state(forCommand: command) == .running)
    }

    @Test("コマンドが空・未指定なら running")
    func emptyCommandFallsBackToRunning() {
        #expect(AgentActivityClassifier.state(forCommand: nil) == .running)
        #expect(AgentActivityClassifier.state(forCommand: "   ") == .running)
    }

    @Test("パス付きの読み取りコマンドは basename で判定する")
    func absolutePathReadCommandIsSearching() {
        #expect(AgentActivityClassifier.state(forCommand: "/usr/bin/grep foo bar") == .searching)
    }

    @Test("承認待ち・質問待ちは waiting")
    func awaitingStatusesAreWaiting() {
        #expect(AgentActivityClassifier.waitingState(for: .awaitingApproval(prompt: "続行?")) == .waiting)
        #expect(AgentActivityClassifier.waitingState(for: .awaitingUserQuestion) == .waiting)
    }

    @Test("待機でない状態は nil（transcript 側で決める）")
    func nonAwaitingStatusesYieldNil() {
        #expect(AgentActivityClassifier.waitingState(for: .running) == nil)
        #expect(AgentActivityClassifier.waitingState(for: .idle) == nil)
        #expect(AgentActivityClassifier.waitingState(for: .starting) == nil)
        #expect(AgentActivityClassifier.waitingState(for: .completed(exitCode: 0)) == nil)
        #expect(AgentActivityClassifier.waitingState(for: .error(message: "boom")) == nil)
    }
}
