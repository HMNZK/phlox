import Testing
@testable import AgentDomain

// MARK: - starting

@Test func starting_sessionStartBecomesIdle() {
    let result = reduce(.starting, applying: .sessionStart)
    #expect(result == .idle)
}

@Test func starting_notificationApproval() {
    let message = "Do you want to Allow this?"
    let result = reduce(.starting, applying: .notification(message: message))
    #expect(result == .awaitingApproval(prompt: message))
}

@Test(arguments: [
    "Task finished",
    "Connected to server",
    "Processing...",
])
func starting_notificationNonApproval(message: String) {
    let result = reduce(.starting, applying: .notification(message: message))
    #expect(result == .starting)
}

@Test(arguments: [
    HookEvent.preToolUse(toolName: "Shell"),
    HookEvent.postToolUse(toolName: "Read"),
    HookEvent.userPromptSubmit(turnId: nil),
])
func starting_workEventsBecomeRunning(event: HookEvent) {
    let result = reduce(.starting, applying: event)
    #expect(result == .running)
}

@Test func starting_stopBecomesIdle() {
    let result = reduce(.starting, applying: .stop(turnId: nil))
    #expect(result == .idle)
}

// MARK: - idle

@Test func idle_sessionStartStaysIdle() {
    let result = reduce(.idle, applying: .sessionStart)
    #expect(result == .idle)
}

@Test func idle_notificationApproval() {
    let message = "permission required"
    let result = reduce(.idle, applying: .notification(message: message))
    #expect(result == .awaitingApproval(prompt: message))
}

@Test func idle_notificationNonApprovalStaysIdle() {
    let result = reduce(.idle, applying: .notification(message: "Ready"))
    #expect(result == .idle)
}

@Test(arguments: [
    HookEvent.preToolUse(toolName: "Grep"),
    HookEvent.postToolUse(toolName: "Write"),
    HookEvent.userPromptSubmit(turnId: nil),
])
func idle_workEventsBecomeRunning(event: HookEvent) {
    let result = reduce(.idle, applying: event)
    #expect(result == .running)
}

@Test func idle_stopStaysIdle() {
    let result = reduce(.idle, applying: .stop(turnId: nil))
    #expect(result == .idle)
}

// MARK: - running

@Test func running_sessionStartBecomesIdle() {
    let result = reduce(.running, applying: .sessionStart)
    #expect(result == .idle)
}

@Test func running_notificationApproval() {
    let message = "Please approve this action"
    let result = reduce(.running, applying: .notification(message: message))
    #expect(result == .awaitingApproval(prompt: message))
}

@Test func running_notificationNonApproval() {
    let result = reduce(.running, applying: .notification(message: "Done"))
    #expect(result == .running)
}

@Test(arguments: [
    HookEvent.preToolUse(toolName: "Grep"),
    HookEvent.postToolUse(toolName: "Write"),
    HookEvent.userPromptSubmit(turnId: nil),
])
func running_workEventsStayRunning(event: HookEvent) {
    let result = reduce(.running, applying: event)
    #expect(result == .running)
}

@Test func running_stopBecomesIdle() {
    let result = reduce(.running, applying: .stop(turnId: nil))
    #expect(result == .idle)
}

@Test func preToolUseExitPlanMode_becomesAwaiting() {
    let result = reduce(.running, applying: .preToolUse(toolName: "ExitPlanMode"))
    #expect(result == .awaitingApproval(prompt: "Plan approval requested"))
}

@Test func preToolUseExitPlanMode_fromIdle_becomesAwaiting() {
    let result = reduce(.idle, applying: .preToolUse(toolName: "ExitPlanMode"))
    #expect(result == .awaitingApproval(prompt: "Plan approval requested"))
}

@Test func preToolUseNonExitPlanMode_staysRunning() {
    let result = reduce(.running, applying: .preToolUse(toolName: "Shell"))
    #expect(result == .running)
}

// MARK: - awaitingApproval

@Test func awaitingApproval_sessionStartBecomesIdle() {
    let result = reduce(.awaitingApproval(prompt: "Allow?"), applying: .sessionStart)
    #expect(result == .idle)
}

@Test func awaitingApproval_userPromptSubmit() {
    let result = reduce(
        .awaitingApproval(prompt: "Allow?"),
        applying: .userPromptSubmit(turnId: nil)
    )
    #expect(result == .running)
}

@Test(arguments: [
    HookEvent.preToolUse(toolName: "Shell"),
    HookEvent.postToolUse(toolName: "Read"),
])
func awaitingApproval_toolEventsBecomeRunning(event: HookEvent) {
    let result = reduce(.awaitingApproval(prompt: "Allow?"), applying: event)
    #expect(result == .running)
}

@Test func awaitingApproval_notificationApprovalKeepsPrompt() {
    let message = "Do you want to proceed?"
    let result = reduce(.awaitingApproval(prompt: "old"), applying: .notification(message: message))
    #expect(result == .awaitingApproval(prompt: message))
}

@Test func awaitingApproval_notificationNonApprovalStaysAwaiting() {
    let result = reduce(.awaitingApproval(prompt: "Allow?"), applying: .notification(message: "Done"))
    #expect(result == .awaitingApproval(prompt: "Allow?"))
}

@Test func awaitingApproval_stopStaysAwaiting() {
    let prompt = "approve?"
    let result = reduce(.awaitingApproval(prompt: prompt), applying: .stop(turnId: nil))
    #expect(result == .awaitingApproval(prompt: prompt))
}

// MARK: - terminal states

@Test(arguments: [
    HookEvent.sessionStart,
    HookEvent.notification(message: "late message"),
    HookEvent.stop(turnId: nil),
    HookEvent.preToolUse(toolName: "Shell"),
    HookEvent.userPromptSubmit(turnId: nil),
])
func completed_isTerminal(event: HookEvent) {
    let result = reduce(.completed(exitCode: 0), applying: event)
    #expect(result == .completed(exitCode: 0))
}

@Test(arguments: [
    HookEvent.sessionStart,
    HookEvent.notification(message: "late message"),
    HookEvent.stop(turnId: nil),
    HookEvent.postToolUse(toolName: "Read"),
])
func error_isTerminal(event: HookEvent) {
    let message = "something went wrong"
    let result = reduce(.error(message: message), applying: event)
    #expect(result == .error(message: message))
}

// MARK: - approval pattern detection (case insensitive)

@Test(arguments: [
    "Please Allow access",
    "needs your approve",
    "permission denied?",
    "Do you want to continue",
    "Continue? y/n",
    "ALLOW",
    "APPROVE",
    "PERMISSION",
    "DO YOU WANT",
    "Y/N",
])
func approvalPatternsAreDetected(message: String) {
    let fromStarting = reduce(.starting, applying: .notification(message: message))
    #expect(fromStarting == .awaitingApproval(prompt: message))

    let fromIdle = reduce(.idle, applying: .notification(message: message))
    #expect(fromIdle == .awaitingApproval(prompt: message))

    let fromRunning = reduce(.running, applying: .notification(message: message))
    #expect(fromRunning == .awaitingApproval(prompt: message))
}

// MARK: - approval pattern false positives (characterization)

/// 特性化: 承認要求ではない通知も部分文字列マッチで awaitingApproval に
/// 誤検知される現挙動の記録。検知ロジックを改善する際はこのテストを
/// 「誤検知しない」期待へ反転させること。
@Test(arguments: [
    "Permission denied",
    "Allowed tools updated",
    "The request was approved automatically",
])
func approvalPatterns_knownFalsePositivesCurrentlyTriggerAwaitingApproval(message: String) {
    let result = reduce(.running, applying: .notification(message: message))
    #expect(result == .awaitingApproval(prompt: message))
}
