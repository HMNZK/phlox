import Foundation
import Testing
import PhloxCore
import Features

/// task-9 受け入れテスト（PM 著・実装役はアサーション編集禁止）。
/// API 拡張のセッション操作系 UI 統合の観測可能な振る舞いを凍結する:
///  1. 停止（interrupt）: running のときだけ呼ぶ / 409（非対応）はエラーバナーでなく無効化で扱う
///  2. usage 表示: ターン完了（running→idle）検出時に取得
///  3. 差分ポーリング: refresh が messagesDelta を使い、snapshot=全置換 / 差分=append / cursor 引き継ぎ /
///     404・501 は messages() 全量取得へフォールバック
/// acceptance_tests のアサーションは変更禁止。テストハーネスの欠陥を見つけたら PM に報告し
/// 承認のうえハーネス部分（MockAPI）に限り修理してよい。
@MainActor
struct SessionControlAcceptanceTests {
    private func makeSession(status: SessionStatus) -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: status,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - 1. 停止（interrupt）

    @Test("running のとき stop() が interrupt を1回呼ぶ")
    func stopCallsInterruptWhenRunning() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        await vm.stop()

        #expect(await api.interruptCount == 1)
    }

    @Test("非 running のとき stop() は interrupt を呼ばない")
    func stopIgnoredWhenNotRunning() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        await vm.stop()

        #expect(await api.interruptCount == 0)
    }

    @Test("interrupt が 409 を返したら canInterrupt=false・エラーバナーは出さない")
    func interrupt409DisablesWithoutErrorBanner() async {
        let api = MockAPI()
        await api.setInterruptOutcome(.failure(.server(status: 409, message: "interrupt 非対応")))
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        await vm.stop()

        #expect(vm.canInterrupt == false, "409（非対応）は停止 UI を無効化する")
        #expect(vm.loadError == nil, "409 をエラーバナーに出さない")
    }

    // MARK: - 2. usage 表示

    @Test("ターン完了（running→idle）を refresh が検出したら usage を取得して表示する")
    func usageFetchedOnTurnCompletion() async {
        let api = MockAPI(messagesOutcome: .success([]))
        await api.setSessions([makeSession(status: .idle)]) // 遷移先: idle
        await api.setUsageOutcome(.success(TurnUsage(costUSD: 0.1234, contextUsedTokens: 1000, contextWindowTokens: 200_000)))
        // 開始状態は running（session.status）。refresh で listSessions が idle を返し running→idle 遷移。
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        await vm.refresh()

        #expect(vm.turnUsage?.costUSD == 0.1234)
        #expect(vm.turnUsage?.contextUsedTokens == 1000)
    }

    @Test("running のままの refresh では usage を取得しない")
    func usageNotFetchedWhileStillRunning() async {
        let api = MockAPI(messagesOutcome: .success([]))
        await api.setSessions([makeSession(status: .running)]) // 遷移なし
        await api.setUsageOutcome(.success(TurnUsage(costUSD: 0.99, contextUsedTokens: 1, contextWindowTokens: 2)))
        let vm = SessionDetailViewModel(session: makeSession(status: .running), api: api)

        await vm.refresh()

        #expect(await api.usageCount == 0, "ターン継続中は usage を叩かない")
        #expect(vm.turnUsage == nil)
    }

    // MARK: - 3. 差分ポーリング

    @Test("messagesDelta が isSnapshot=true を返すと手元を全置換する")
    func snapshotReplacesMessages() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "stale", text: "古い全量")]))
        let snapshot = MessagesDelta(
            messages: [.user(id: "m1", text: "質問"), .agent(id: "m2", text: "回答")],
            cursor: "c1", isSnapshot: true
        )
        await api.setMessagesDeltaScript([.success(snapshot)])
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        await vm.refresh()

        #expect(vm.chatMessages == [.user(id: "m1", text: "質問"), .agent(id: "m2", text: "回答")])
    }

    @Test("snapshot の後の差分は append され、2回目の since に前回 cursor が渡る")
    func deltaAppendsAndCarriesCursor() async {
        let api = MockAPI(messagesOutcome: .success([]))
        let snapshot = MessagesDelta(messages: [.agent(id: "m1", text: "1")], cursor: "c1", isSnapshot: true)
        let delta = MessagesDelta(messages: [.agent(id: "m2", text: "2")], cursor: "c2", isSnapshot: false)
        await api.setMessagesDeltaScript([.success(snapshot), .success(delta)])
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        await vm.refresh() // snapshot: since=nil
        await vm.refresh() // delta: since=c1

        #expect(vm.chatMessages == [.agent(id: "m1", text: "1"), .agent(id: "m2", text: "2")], "差分は append")
        #expect(await api.deltaSinceLog == [nil, "c1"], "2回目の since に前回 cursor を渡す")
    }

    @Test("messagesDelta が 501（旧サーバー）を返すと messages() 全量取得へフォールバックする")
    func fallsBackToFullMessagesOn501() async {
        // messagesDeltaScript を空にすると MockAPI は 501 を投げる（旧サーバー模擬）。
        let fallback: [ChatMessage] = [.agent(id: "f1", text: "全量フォールバック")]
        let api = MockAPI(messagesOutcome: .success(fallback))
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        await vm.refresh()

        #expect(await api.deltaSinceLog.isEmpty == false, "まず messagesDelta を試みる")
        #expect(vm.chatMessages == fallback, "501 で messages() 全量取得へフォールバック")
    }

    @Test("messagesDelta が 404 を返しても messages() 全量取得へフォールバックする")
    func fallsBackToFullMessagesOn404() async {
        let fallback: [ChatMessage] = [.agent(id: "f2", text: "404 フォールバック")]
        let api = MockAPI(messagesOutcome: .success(fallback))
        await api.setMessagesDeltaScript([.failure(.notFound)])
        let vm = SessionDetailViewModel(session: makeSession(status: .idle), api: api)

        await vm.refresh()

        #expect(await api.deltaSinceLog.isEmpty == false, "まず messagesDelta を試みる")
        #expect(vm.chatMessages == fallback)
    }
}
