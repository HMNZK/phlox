import Foundation
import Testing
@testable import StructuredChatKit

@Test func oneShotRunnerTimeoutThrowsTypedTimeoutError() async throws {
    let runner = OneShotProcessRunner(timeout: 0.2)

    do {
        _ = try await runner.run(
            command: "/bin/sleep",
            arguments: ["2"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil
        )
        Issue.record("Expected timeout to throw")
    } catch let error as OneShotProcessTimeoutError {
        #expect(error.timeout == 0.2)
        #expect(error.errorDescription?.contains("timed out") == true)
    } catch {
        Issue.record("Expected OneShotProcessTimeoutError, got \(error)")
    }
}

@Test func oneShotTimeoutOutcomeSuppressesKillAfterTerminationClaim() {
    let outcome = OneShotTimeoutOutcome()
    var didKill = false

    #expect(outcome.claimTermination())
    #expect(!outcome.claimTimeout {
        didKill = true
    })
    #expect(!didKill)
}

@Test func oneShotTimeoutOutcomeRunsKillInsideTimeoutClaimOnlyOnce() {
    let outcome = OneShotTimeoutOutcome()
    var killCount = 0

    #expect(outcome.claimTimeout {
        killCount += 1
    })
    #expect(killCount == 1)
    #expect(!outcome.claimTermination())
    #expect(!outcome.claimTimeout {
        killCount += 1
    })
    #expect(killCount == 1)
}
