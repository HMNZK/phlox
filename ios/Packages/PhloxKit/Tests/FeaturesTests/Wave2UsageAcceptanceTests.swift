// PM著・凍結。アサーション変更禁止。
// このテストファイル自体（ハーネス）に欠陥が見つかった場合のみ、PM 承認のうえで修理可。
//
// task-8: Usageリミット画面。
// 対象仕様: tasks/task-8.md
// 公開API契約（実装役が Features/Usage/ 配下に作る）:
//   - UsageViewModel(api: PhloxAPI)
//   - state: UsageViewModel.State（.idle / .loading / .loaded / .failed の Equatable enum）
//   - agents: [CLIUsage]（読み取り専用。cliUsage() の結果をそのまま保持）
//   - isEmpty: Bool（.loaded かつ agents.isEmpty のとき true）
//   - load() async — api.cliUsage() を呼び agents / state を更新する。失敗時は state = .failed。
//   - static UsageViewModel.isUnavailable(_ usage: CLIUsage) -> Bool
//     （usage.state == .unavailable のときだけ true。ok は buckets をそのまま利用可能とみなす）
//
// このテストは PhloxAPI に準拠する専用スタブ（UsageStubAPI）で [CLIUsage] を供給する。

import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite struct Wave2UsageAcceptanceTests {
    // MARK: - 起動で cliUsage() が呼ばれ agents に反映される

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

    // MARK: - state=ok は buckets を、unavailable は利用不可フラグを持つ

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

    // MARK: - 取得失敗時にエラー状態、0件で空状態フラグ

    @Test func loadFailureSetsFailedState() async {
        let stub = UsageStubAPI(usageOutcome: .failure(.server(status: 500, message: "boom")))
        let vm = UsageViewModel(api: stub)

        await vm.load()

        #expect(vm.state == .failed)
        #expect(vm.agents.isEmpty)
    }

    @Test func emptyResultSetsEmptyFlag() async {
        let stub = UsageStubAPI(usageOutcome: .success([]))
        let vm = UsageViewModel(api: stub)

        await vm.load()

        #expect(vm.state == .loaded)
        #expect(vm.agents.isEmpty)
        #expect(vm.isEmpty == true)
    }
}

/// task-8 専用の PhloxAPI スタブ。cliUsage() の結果を差し替え可能にし、呼び出し回数を記録する。
private actor UsageStubAPI: PhloxAPI {
    let usageOutcome: Result<[CLIUsage], PhloxError>
    private(set) var cliUsageCallCount = 0

    init(usageOutcome: Result<[CLIUsage], PhloxError>) {
        self.usageOutcome = usageOutcome
    }

    func listSessions() async throws -> [Session] { [] }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(
            id: "x",
            name: "x",
            agent: .claudeCode,
            status: .starting,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func waitUntilReady(sessionID: String) async throws -> Bool { true }

    func send(_ request: SendRequest) async throws -> SendResult {
        SendResult(accepted: true)
    }

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
