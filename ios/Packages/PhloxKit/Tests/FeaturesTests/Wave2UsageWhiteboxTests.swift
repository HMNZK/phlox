import Foundation
import Testing
import PhloxCore
@testable import Features

/// task-8 白箱: UsageViewModel の表示写像と状態フラグを検証する。
@MainActor
@Suite struct Wave2UsageWhiteboxTests {
    @Test func isUnavailableOnlyForUnavailableState() {
        let ok = CLIUsage(kind: .claudeCode, state: .ok, buckets: [], updatedAt: nil, dataAsOf: nil)
        let unavailable = CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil)

        #expect(UsageViewModel.isUnavailable(ok) == false)
        #expect(UsageViewModel.isUnavailable(unavailable) == true)
    }

    @Test func isEmptyOnlyWhenLoadedWithNoAgents() async {
        let stub = UsageWhiteboxStubAPI(usageOutcome: .success([]))
        let vm = UsageViewModel(api: stub)

        #expect(vm.isEmpty == false)

        await vm.load()

        #expect(vm.state == .loaded)
        #expect(vm.isEmpty == true)
    }

    @Test func isEmptyFalseWhenLoadedWithAgents() async {
        let fixture = [
            CLIUsage(kind: .claudeCode, state: .ok, buckets: [], updatedAt: nil, dataAsOf: nil),
        ]
        let stub = UsageWhiteboxStubAPI(usageOutcome: .success(fixture))
        let vm = UsageViewModel(api: stub)

        await vm.load()

        #expect(vm.isEmpty == false)
    }

    @Test func formattedUsedPercentClampsAndRounds() {
        #expect(UsageViewModel.formattedUsedPercent(0) == "0%")
        #expect(UsageViewModel.formattedUsedPercent(42.4) == "42%")
        #expect(UsageViewModel.formattedUsedPercent(42.6) == "43%")
        #expect(UsageViewModel.formattedUsedPercent(100) == "100%")
        #expect(UsageViewModel.formattedUsedPercent(-5) == "0%")
        #expect(UsageViewModel.formattedUsedPercent(150) == "100%")
    }

    @Test func resetsAtLabelNilForMissingDate() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(UsageViewModel.resetsAtLabel(for: nil, now: now) == nil)
    }

    @Test func resetsAtLabelRelativeWithin24Hours() {
        let now = Date(timeIntervalSince1970: 0)
        let inTwoHours = Date(timeIntervalSince1970: 7200)
        #expect(UsageViewModel.resetsAtLabel(for: inTwoHours, now: now) == "あと2時間")
    }

    @Test func resetsAtLabelAbsoluteBeyond24Hours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 0)
        let inThreeDays = Date(timeIntervalSince1970: 86_400 * 3 + 3600)
        #expect(
            UsageViewModel.resetsAtLabel(
                for: inThreeDays,
                now: now,
                calendar: calendar
            ) == "リセット 1/4 01:00"
        )
    }

    @Test func resetsAtLabelPastShowsResetDone() {
        let now = Date(timeIntervalSince1970: 100)
        let past = Date(timeIntervalSince1970: 50)
        #expect(UsageViewModel.resetsAtLabel(for: past, now: now) == "リセット済み")
    }
}

private actor UsageWhiteboxStubAPI: PhloxAPI {
    let usageOutcome: Result<[CLIUsage], PhloxError>

    init(usageOutcome: Result<[CLIUsage], PhloxError>) {
        self.usageOutcome = usageOutcome
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "x", name: "x", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: .distantPast)
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func cliUsage() async throws -> [CLIUsage] {
        try usageOutcome.get()
    }
}
