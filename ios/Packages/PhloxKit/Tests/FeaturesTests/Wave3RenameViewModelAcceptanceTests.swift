import Foundation
import Testing
import PhloxCore
@testable import Features

/// wave-3 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-1.md）。
///
/// 契約: `SessionDetailViewModel` のセッション名変更（rename）フロー。
///  - `displayName` は表示名の単一の源（初期値は session.name）。トップバー中央のタイトルが束縛する。
///  - `beginRename()` は `renameDraft` を現在の `displayName` で初期化し、`isRenamePresented` を true にする。
///  - `commitRename()` は trim 後の `renameDraft` が空 or 現在の `displayName` と同じなら
///    api を呼ばず `isRenamePresented` を false にする（no-op）。
///  - それ以外は `api.rename(sessionID:name:)` を呼び、成功時に `displayName` を更新し
///    `isRenamePresented` を false にする。失敗時は `displayName` を変えない。
@MainActor
@Suite struct Wave3RenameViewModelAcceptanceTests {
    private func makeSession(id: String = "s1", name: String = "Rose") -> Session {
        Session(
            id: id,
            name: name,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func displayNameDefaultsToSessionName() {
        let vm = SessionDetailViewModel(session: makeSession(name: "Rose"), api: RenameRecordingAPI())
        #expect(vm.displayName == "Rose")
    }

    @Test func beginRenameSeedsDraftFromDisplayName() {
        let vm = SessionDetailViewModel(session: makeSession(name: "Rose"), api: RenameRecordingAPI())
        vm.beginRename()
        #expect(vm.renameDraft == "Rose")
        #expect(vm.isRenamePresented == true)
    }

    @Test func commitRenameCallsAPIAndUpdatesDisplayName() async {
        let api = RenameRecordingAPI()
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        vm.renameDraft = "  新しい名前  " // 前後空白は trim される
        await vm.commitRename()

        let log = await api.renameLog
        #expect(log.count == 1)
        #expect(log[0].0 == "s1")
        #expect(log[0].1 == "新しい名前")
        #expect(vm.displayName == "新しい名前")
        #expect(vm.isRenamePresented == false)
    }

    @Test func commitRenameIgnoresEmptyDraft() async {
        let api = RenameRecordingAPI()
        let vm = SessionDetailViewModel(session: makeSession(name: "Rose"), api: api)
        vm.isRenamePresented = true
        vm.renameDraft = "   "

        await vm.commitRename()

        let log = await api.renameLog
        #expect(log.isEmpty)
        #expect(vm.displayName == "Rose")
        #expect(vm.isRenamePresented == false)
    }

    @Test func commitRenameIgnoresUnchangedName() async {
        let api = RenameRecordingAPI()
        let vm = SessionDetailViewModel(session: makeSession(name: "Rose"), api: api)
        vm.renameDraft = "Rose"

        await vm.commitRename()

        let log = await api.renameLog
        #expect(log.isEmpty)
        #expect(vm.displayName == "Rose")
    }

    @Test func commitRenameKeepsNameOnFailure() async {
        let api = RenameRecordingAPI(shouldFail: true)
        let vm = SessionDetailViewModel(session: makeSession(name: "Rose"), api: api)
        vm.renameDraft = "新しい名前"

        await vm.commitRename()

        #expect(vm.displayName == "Rose")
    }
}

/// rename の呼び出しを記録する PhloxAPI モック（actor で Sendable）。
private actor RenameRecordingAPI: PhloxAPI {
    let shouldFail: Bool
    private(set) var renameLog: [(String, String)] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "x", name: "x", agent: .claudeCode, status: .starting, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}

    func rename(sessionID: String, name: String) async throws {
        if shouldFail {
            throw PhloxError.server(status: 500, message: "boom")
        }
        renameLog.append((sessionID, name))
    }
}
