import StructuredChatKit
import Testing
@testable import CursorAgentKit

@Test(arguments: [false, true])
func cancelledCursorSubmissionDoesNotLaunchRunner(afterApproval: Bool) async {
    let runner = MockOneShotProcessRunner()
    let client = CursorChatClient(
        command: "cursor-agent",
        preApprovalPolicy: { _ in
            if afterApproval {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return .approve
        },
        runner: runner
    )
    let submission = Task {
        if !afterApproval {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        do {
            try await client.turnStart([.text("cancelled input")])
            Issue.record("Cancelled submission was accepted")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected submission error: \(error)")
        }
    }
    await submission.value
    #expect(runner.recordedInvocations().isEmpty)
    await client.close()
}
