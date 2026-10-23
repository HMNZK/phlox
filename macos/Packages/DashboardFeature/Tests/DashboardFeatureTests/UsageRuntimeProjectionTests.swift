import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

@Suite @MainActor struct UsageRuntimeProjectionTests {
    @Test func attachmentDoesNotStartUsageProviders() {
        var commands = 0
        let monitor = UsageMonitor(projection: .init(usages: [:], failures: [:])) { _ in commands += 1 }
        monitor.start()
        monitor.start()
        monitor.applyRuntimeSnapshot(.init(usages: [:], failures: [.codex: .init(reason: "rate limit", at: Date())]))
        #expect(commands == 0)
        #expect(monitor.claudeProcess == nil)
        #expect(monitor.failures[.codex]?.reason == "rate limit")
        monitor.stop()
    }

    @Test func disconnectedRefreshRetainsRuntimeStateAndReportsFailure() async {
        enum Disconnected: Error { case offline }
        let usage = CLIUsage(kind: .codex, state: .unavailable(reason: "未取得"), updatedAt: Date())
        let monitor = UsageMonitor(projection: .init(usages: [.codex: usage], failures: [:])) { _ in
            throw Disconnected.offline
        }
        await monitor.refresh()
        #expect(monitor.usages[.codex]?.updatedAt == usage.updatedAt)
        #expect(monitor.runtimeCommandError != nil)
    }
}
