// PM著・凍結。アサーション変更禁止。
// このテストファイル自体（ハーネス）に欠陥が見つかった場合のみ、PM 承認のうえで修理可。
//
// task-5: SessionsOverview（グリッド/シングル切替）の純ロジック。
// 対象仕様: tasks/task-5.md
// 公開API契約（実装役が Features/SessionsOverview/ 配下に作る。View非依存の純状態）:
//   - OverviewMode: Equatable な enum { case grid, single }
//   - SessionsOverviewViewModel(sessions: [Session]) — 純粋な初期化子（Repository 抜きで
//     直接 [Session] を渡せる。sessionStream 連携用の追加初期化子/更新APIは task-5 の裁量。
//     このテストは「モード遷移・grid/single の対象選択・空状態」という純ロジックだけを固定する。
//   - mode: OverviewMode（既定 .grid）
//   - toggleMode() — grid <-> single を反転
//   - gridSessions: [Session] — 全件
//   - singleSession: Session? — 選択中1件（既定=先頭）
//   - selectSession(id: String) — single 対象を明示的に選択
//   - isEmpty: Bool — sessions.isEmpty

import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite struct Wave2OverviewAcceptanceTests {
    private func makeSession(id: String) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func defaultModeIsGridAndToggleFlipsBetweenGridAndSingle() {
        let vm = SessionsOverviewViewModel(sessions: [makeSession(id: "s1")])

        #expect(vm.mode == .grid)

        vm.toggleMode()
        #expect(vm.mode == .single)

        vm.toggleMode()
        #expect(vm.mode == .grid)
    }

    @Test func gridShowsAllSessionsAndSingleDefaultsToFirst() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2"), makeSession(id: "s3")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        #expect(vm.gridSessions.map(\.id) == ["s1", "s2", "s3"])
        #expect(vm.singleSession?.id == "s1")
    }

    @Test func selectingSessionUpdatesSingleSessionWithoutAffectingGrid() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2"), makeSession(id: "s3")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        vm.selectSession(id: "s2")

        #expect(vm.singleSession?.id == "s2")
        #expect(vm.gridSessions.map(\.id) == ["s1", "s2", "s3"])
    }

    @Test func emptySessionsSetsEmptyFlagAndNilSingleSession() {
        let vm = SessionsOverviewViewModel(sessions: [])

        #expect(vm.isEmpty == true)
        #expect(vm.gridSessions.isEmpty)
        #expect(vm.singleSession == nil)
    }
}
