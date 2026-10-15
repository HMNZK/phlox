import Foundation
import StructuredChatKit
import Testing
@testable import ClaudeAgentKit

/// 認証・ネットワーク・実CLIに依存する明示実行専用の統合検証。
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PHLOX_USAGE_LIVE"] == "1"))
struct ClaudeUsageLiveTests {
    private var command: String { ProcessInfo.processInfo.environment["PHLOX_USAGE_CLAUDE"] ?? "claude" }

    @Test func dedicatedThreeCyclesWithoutConversation() async throws {
        let process = ClaudeUsageProcess(command: command, environment: ProcessInfo.processInfo.environment)
        do {
            for cycle in 1...3 {
                if cycle > 1 { try await Task.sleep(for: .seconds(60)) }
                let result = try await process.fetchRateLimits()
                #expect(result.fiveHour != nil)
                #expect(result.sevenDay != nil)
                print("LIVE usage cycle \(cycle): fiveHour=\(result.fiveHour?.usedPercentage ?? -1), weekly=\(result.sevenDay?.usedPercentage ?? -1)")
            }
        } catch {
            await process.shutdown()
            throw error
        }
        await process.shutdown()
    }

    @Test func conversationDeliversUsageWithoutGetUsage() async throws {
        let client = ClaudeChatClient(command: command, transportFactory: { command, _, environment, _ in
            LineDelimitedProcessTransport(command: command,
                arguments: ClaudeUsageProcess.arguments + ["--include-partial-messages", "--model", "haiku",
                    "--system-prompt", "Reply with exactly OK.", "--max-budget-usd", "0.25"], environment: environment)
        })
        try await client.start()
        let timeout = Task { try await Task.sleep(for: .seconds(45)); await client.close() }
        do {
            try await client.turnStart([.text("Reply exactly OK.")])
            var received: AgentRateLimitsSnapshot?
            for await event in client.events {
                if case .rateLimitsUpdated(let snapshot) = event { received = snapshot }
                if case .turnCompleted = event { break }
                if case .error(let message) = event { Issue.record("\(message)"); break }
            }
            #expect(received?.fiveHour != nil)
            #expect(received?.sevenDay != nil)
        } catch {
            timeout.cancel()
            await client.close()
            throw error
        }
        timeout.cancel()
        await client.close()
    }
}
