import Testing
@testable import Features

struct HistoryPullAcceptanceTests {
    @Test("上端を引いて離すと1回だけ展開し、戻すか履歴がなければ展開しない")
    func pullReleaseAndCancellation() {
        var pull = SessionDetailHistoryPull()
        pull.update(offset: 0, hasEarlierMessages: true)
        let initial = pull.finish()
        #expect(!initial)
        pull.update(offset: -24, hasEarlierMessages: true)
        #expect(pull.isArmed)
        let released = pull.finish()
        #expect(released)
        let repeated = pull.finish()
        #expect(!repeated)
        pull.update(offset: -24, hasEarlierMessages: true)
        pull.update(offset: 0, hasEarlierMessages: true)
        let cancelled = pull.finish()
        #expect(!cancelled)
        pull.update(offset: -24, hasEarlierMessages: false)
        let noHistory = pull.finish()
        #expect(!noHistory)
    }
}
