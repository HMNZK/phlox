import Foundation
import Testing
import AgentDomain
import PhloxCore
@testable import Features

@MainActor
@Suite("使用量リング")
struct UsageViewModelTests {
    private let asOf = Self.date(day: 17, hour: 16, minute: 12)

    @Test("使用量から残りを丸め、0% に最小の弧を残す")
    func remainingPercentAndRingFraction() {
        #expect(UsageRingPresentation.remainingPercent(usedPercent: 28) == 72)
        #expect(UsageRingPresentation.remainingPercent(usedPercent: 42.4) == 58)
        #expect(UsageRingPresentation.remainingPercent(usedPercent: 42.6) == 57)
        #expect(UsageRingPresentation.remainingPercent(usedPercent: -5) == 100)
        #expect(UsageRingPresentation.remainingPercent(usedPercent: 150) == 0)
        #expect(UsageRingPresentation.remainingFraction(usedPercent: 0) == 1)
        #expect(UsageRingPresentation.remainingFraction(usedPercent: 100) == 0.02)
    }

    @Test("残り20%未満だけ注意色になる")
    func cautionThresholdUsesRemainingPercent() {
        #expect(!UsageRingPresentation.isLowRemaining(usedPercent: 80))
        #expect(UsageRingPresentation.isLowRemaining(usedPercent: 80.01))
        #expect(UsageRingPresentation.isLowRemaining(usedPercent: 100))
    }

    @Test("エージェント順と枠の並び、Claude だけの短い表示")
    func agentsAreOrderedAndHaveExpectedSlots() {
        let agents = UsageRingPresentation.agents(from: [
            agent(.cursor, buckets: [bucket("api", "API", used: 5)]),
            agent(.codex, buckets: [bucket("weekly", "週次", used: 15)]),
            agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 28)]),
        ])

        #expect(agents.map(\.kind) == [.claudeCode, .codex, .cursor])
        #expect(agents[0].buckets.map(\.id) == ["5h", "weekly"])
        #expect(agents[0].buckets.map(\.ringLabel) == ["5h", "7d"])
        #expect(agents[1].buckets.map(\.ringLabel) == [nil, nil])
        #expect(agents[2].buckets.map(\.id) == ["auto", "api"])
        #expect(agents[2].buckets.map(\.ringLabel) == [nil, nil])
        #expect(agents[0].buckets[1].remainingPercent == nil)
        #expect(agents[0].buckets[1].remainingFraction == nil)
        #expect(agents[0].buckets[1].isLow == false)
        #expect(agents[0].buckets[1].label == "週次")
    }

    @Test("取得できないエージェントと欠けた枠を分けて表す")
    func unavailableAndMissingBucketsAreDistinct() {
        let agents = UsageRingPresentation.agents(from: [
            CLIUsage(kind: .claudeCode, state: .ok, buckets: [], updatedAt: nil, dataAsOf: nil),
            CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil),
        ])

        #expect(!agents[0].isUnavailable)
        #expect(agents[0].buckets.allSatisfy { $0.value == nil })
        #expect(agents[1].isUnavailable)
        #expect(agents[1].buckets.allSatisfy { $0.value == nil })
        #expect(agents[2].isUnavailable)
        #expect(UsageRingPresentation.valueText(for: agents[0].buckets[0]) == "値なし")
    }

    @Test("5時間枠は残り時間、週次は日時、Cursor はリセットなし")
    func resetTextMatchesUsagePopoverFormat() {
        let now = Self.date(day: 17, hour: 16, minute: 12)
        let fiveHour = bucket("5h", "5時間", used: 28, resetsAt: Self.date(day: 17, hour: 19, minute: 24))
        let weekly = bucket("weekly", "週次", used: 60, resetsAt: Self.date(day: 20, hour: 14, minute: 0))
        let cursor = bucket("auto", "Auto", used: 20, resetsAt: Self.date(day: 20, hour: 14, minute: 0))
        let claude = UsageRingPresentation.agents(from: [
            agent(.claudeCode, buckets: [fiveHour, weekly]),
        ])[0]

        #expect(UsageRingPresentation.resetText(for: claude.buckets[0], agent: .claudeCode, now: now, timeZone: japanTimeZone) == "03:12")
        #expect(UsageRingPresentation.resetText(for: claude.buckets[1], agent: .claudeCode, now: now, timeZone: japanTimeZone) == "10/20 14:00")
        #expect(UsageRingPresentation.resetText(for: UsageRingPresentation.agents(from: [agent(.cursor, buckets: [cursor])])[2].buckets[0], agent: .cursor, now: now, timeZone: japanTimeZone) == nil)
    }

    @Test("行の状態文言は更新中を優先し、古い値には取得時刻を出す")
    func statusTextShowsRefreshingAndStaleTime() {
        #expect(UsageRingPresentation.statusText(isRefreshing: true, isStale: true, asOf: asOf, timeZone: japanTimeZone) == "更新中…")
        #expect(UsageRingPresentation.statusText(isRefreshing: false, isStale: true, asOf: asOf, timeZone: japanTimeZone) == "16:12 時点")
        #expect(UsageRingPresentation.statusText(isRefreshing: false, isStale: false, asOf: asOf, timeZone: japanTimeZone) == nil)
        #expect(UsageRingPresentation.staleNotice(asOf: asOf, timeZone: japanTimeZone) == "16:12 時点の値です。更新できませんでした。一覧を引っ張ると取り直します")
        #expect(UsageRingPresentation.popoverColumnHeaders == ["枠", "残り", "リセット"])
        #expect(UsageRingPresentation.unavailableText == "取得できません")
        #expect(UsageRingPresentation.rowAccessibilityHint == "使用量の詳細を表示")
    }

    @Test("VoiceOver の通常・注意・値なし・取得不可・古い値・更新中")
    func accessibilityLabelCoversUsageStates() {
        let normal = UsageRingPresentation.agents(from: [
            agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 28), bucket("weekly", "週次", used: 60)]),
            agent(.codex, buckets: [bucket("5h", "5時間", used: 1), bucket("weekly", "週次", used: 15)]),
            agent(.cursor, buckets: [bucket("auto", "Auto", used: 20), bucket("api", "API", used: 5)]),
        ])
        #expect(UsageRingPresentation.accessibilityLabel(agents: normal, isRefreshing: false, isStale: false, asOf: nil, timeZone: japanTimeZone)
            == "使用量。Claude 5時間 残り 72%、週次 残り 40%。Codex 5時間 残り 99%、週次 残り 85%。Cursor Auto 残り 80%、API 残り 95%。")
        #expect(UsageRingPresentation.valueText(for: normal[0].buckets[0]) == "残り 72%")

        let low = UsageRingPresentation.agents(from: [agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 88), bucket("weekly", "週次", used: 82)])])
        #expect(UsageRingPresentation.accessibilityLabel(agents: low, isRefreshing: false, isStale: false, asOf: nil, timeZone: japanTimeZone)
            == "使用量。Claude 5時間 残り 12%、残りわずか、週次 残り 18%、残りわずか。Codex 取得できません。Cursor 取得できません。")
        #expect(UsageRingPresentation.valueText(for: low[0].buckets[0]) == "残り 12%")

        let unavailable = UsageRingPresentation.agents(from: [
            agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 28)]),
            CLIUsage(kind: .codex, state: .unavailable, buckets: [], updatedAt: nil, dataAsOf: nil),
        ])
        #expect(UsageRingPresentation.accessibilityLabel(agents: unavailable, isRefreshing: false, isStale: false, asOf: nil, timeZone: japanTimeZone)
            == "使用量。Claude 5時間 残り 72%、週次 値なし。Codex 取得できません。Cursor 取得できません。")
        #expect(UsageRingPresentation.accessibilityLabel(agents: normal, isRefreshing: false, isStale: true, asOf: asOf, timeZone: japanTimeZone)
            == "16時12分時点の値。更新できませんでした。使用量。Claude 5時間 残り 72%、週次 残り 40%。Codex 5時間 残り 99%、週次 残り 85%。Cursor Auto 残り 80%、API 残り 95%。")
        #expect(UsageRingPresentation.accessibilityLabel(agents: normal, isRefreshing: true, isStale: false, asOf: asOf, timeZone: japanTimeZone)
            == "更新中。使用量。Claude 5時間 残り 72%、週次 残り 40%。Codex 5時間 残り 99%、週次 残り 85%。Cursor Auto 残り 80%、API 残り 95%。")
    }

    @Test("初回取得前・0件・失敗で前の値なしは行を出さない")
    func rowIsHiddenUntilAValueExists() async {
        let stub = UsageStubAPI(outcomes: [.success([]), .failure(.server(status: 500, message: "boom"))])
        let vm = UsageViewModel(api: stub)

        #expect(!vm.shouldShowRow)
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.agents.isEmpty)
        #expect(!vm.shouldShowRow)
        await vm.load()
        #expect(vm.state == .failed)
        #expect(!vm.shouldShowRow)
    }

    @Test("取得に失敗したら前の値を古い値として残す")
    func failedRefreshRetainsLastSuccessfulUsage() async {
        let values = [agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 28)])]
        let stub = UsageStubAPI(outcomes: [.success(values), .failure(.server(status: 500, message: "boom"))])
        let fixedAsOf = asOf
        let vm = UsageViewModel(
            api: stub,
            agents: [],
            state: .idle,
            lastSuccessfulAt: nil,
            now: { fixedAsOf }
        )

        await vm.load()
        #expect(vm.shouldShowRow)
        #expect(vm.asOfDate == asOf)
        await vm.load()

        #expect(vm.state == .failed)
        #expect(vm.agents == values)
        #expect(vm.shouldShowRow)
        #expect(vm.isStale)
        #expect(vm.asOfDate == asOf)
        let count = await stub.cliUsageCallCount
        #expect(count == 2)
    }

    @Test("取得中は前の値を保持し、重複取得しない")
    func loadingRetainsValuesAndCoalescesRequests() async {
        let values = [agent(.claudeCode, buckets: [bucket("5h", "5時間", used: 28)])]
        let stub = UsageStubAPI(outcomes: [.success(values)], pausesNextRequest: true)
        let vm = UsageViewModel(api: stub, agents: values, state: .loaded, lastSuccessfulAt: asOf)
        let request = Task { await vm.load() }
        await stub.waitUntilPausedRequest()

        #expect(vm.state == .loading)
        #expect(vm.isRefreshing)
        #expect(vm.shouldShowRow)
        #expect(vm.agents == values)
        await vm.load()
        let count = await stub.cliUsageCallCount
        #expect(count == 1)
        await stub.resumePausedRequest()
        await request.value
        #expect(vm.state == .loaded)
        #expect(vm.agents == values)
    }

    private static var japanTimeZone: TimeZone { TimeZone(secondsFromGMT: 9 * 60 * 60)! }

    private var japanTimeZone: TimeZone { Self.japanTimeZone }

    private func agent(_ kind: AgentKind, buckets: [UsageBucket]) -> CLIUsage {
        CLIUsage(kind: kind, state: .ok, buckets: buckets, updatedAt: asOf, dataAsOf: nil)
    }

    private func bucket(_ id: String, _ label: String, used: Double, resetsAt: Date? = nil) -> UsageBucket {
        UsageBucket(id: id, label: label, usedPercent: used, resetsAt: resetsAt)
    }

    private static func date(day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.japanTimeZone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
}

private actor UsageStubAPI: PhloxAPI {
    private var outcomes: [Result<[CLIUsage], PhloxError>]
    private var pausesNextRequest: Bool
    private var pausedContinuation: CheckedContinuation<[CLIUsage], Error>?
    private var pausedOutcome: Result<[CLIUsage], PhloxError>?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var cliUsageCallCount = 0

    init(outcomes: [Result<[CLIUsage], PhloxError>], pausesNextRequest: Bool = false) {
        self.outcomes = outcomes
        self.pausesNextRequest = pausesNextRequest
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "x", name: "x", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: .distantPast)
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func cliUsage() async throws -> [CLIUsage] {
        cliUsageCallCount += 1
        let outcome = outcomes.isEmpty ? .success([]) : outcomes.removeFirst()
        guard pausesNextRequest else { return try outcome.get() }
        pausesNextRequest = false
        pausedOutcome = outcome
        return try await withCheckedThrowingContinuation { continuation in
            pausedContinuation = continuation
            pauseWaiters.forEach { $0.resume() }
            pauseWaiters.removeAll()
        }
    }

    func waitUntilPausedRequest() async {
        if pausedContinuation != nil { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func resumePausedRequest() {
        let outcome = pausedOutcome ?? .success([])
        pausedContinuation?.resume(with: outcome.mapError { $0 as Error })
        pausedContinuation = nil
        pausedOutcome = nil
    }
}
