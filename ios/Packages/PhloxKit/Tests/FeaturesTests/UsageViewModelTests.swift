import Foundation
import Testing
import PhloxCore
@testable import Features

/// Usage リミット画面の ViewModel: 取得（成功・失敗・空）、利用不可の判定、表示写像。
@MainActor
@Suite("Usage view model") struct UsageViewModelTests {
    @Test func loadFetchesCliUsageAndPopulatesAgents() async {
        let fixture: [CLIUsage] = [
            CLIUsage(
                kind: .claudeCode,
                state: .ok,
                buckets: [UsageBucket(id: "5h", label: "5-hour", usedPercent: 42.0, resetsAt: nil)],
                updatedAt: nil,
                dataAsOf: nil
            ),
            CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil),
        ]
        let stub = UsageStubAPI(usageOutcome: .success(fixture))
        let vm = UsageViewModel(api: stub)

        await vm.load()

        #expect(vm.agents == fixture)
        #expect(vm.state == .loaded)
        let callCount = await stub.cliUsageCallCount
        #expect(callCount == 1)
    }

    @Test func okStateExposesBucketsAndUnavailableStateFlagsUnavailable() async {
        let okBuckets = [UsageBucket(id: "5h", label: "5-hour", usedPercent: 10.0, resetsAt: nil)]
        let fixture: [CLIUsage] = [
            CLIUsage(kind: .claudeCode, state: .ok, buckets: okBuckets, updatedAt: nil, dataAsOf: nil),
            CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil),
        ]
        let stub = UsageStubAPI(usageOutcome: .success(fixture))
        let vm = UsageViewModel(api: stub)
        await vm.load()

        let claude = vm.agents.first { $0.kind == .claudeCode }
        let codex = vm.agents.first { $0.kind == .codex }

        #expect(claude?.buckets == okBuckets)
        #expect(UsageViewModel.isUnavailable(claude!) == false)
        #expect(UsageViewModel.isUnavailable(codex!) == true)
    }

    @Test func loadFailureSetsFailedState() async {
        let stub = UsageStubAPI(usageOutcome: .failure(.server(status: 500, message: "boom")))
        let vm = UsageViewModel(api: stub)

        await vm.load()

        #expect(vm.state == .failed)
        #expect(vm.agents.isEmpty)
    }

    @Test func isEmptyOnlyWhenLoadedWithNoAgents() async {
        let stub = UsageStubAPI(usageOutcome: .success([]))
        let vm = UsageViewModel(api: stub)

        #expect(vm.isEmpty == false)

        await vm.load()

        #expect(vm.state == .loaded)
        #expect(vm.agents.isEmpty)
        #expect(vm.isEmpty == true)
    }

    @Test func isEmptyFalseWhenLoadedWithAgents() async {
        let fixture = [
            CLIUsage(kind: .claudeCode, state: .ok, buckets: [], updatedAt: nil, dataAsOf: nil),
        ]
        let stub = UsageStubAPI(usageOutcome: .success(fixture))
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

/// cliUsage() の結果を差し替え可能にし、呼び出し回数を記録する PhloxAPI スタブ。
private actor UsageStubAPI: PhloxAPI {
    let usageOutcome: Result<[CLIUsage], PhloxError>
    private(set) var cliUsageCallCount = 0

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
        cliUsageCallCount += 1
        return try usageOutcome.get()
    }
}
