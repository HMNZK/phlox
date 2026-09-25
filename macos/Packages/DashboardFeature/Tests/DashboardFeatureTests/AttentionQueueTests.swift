// 01 E1・B1: 対応待ち（承認待ち・質問待ち・エラー・無応答）の一覧と ⌘J の巡回順。

import Foundation
import AgentDomain
import DesignSystem
import Testing
@testable import DashboardFeature

@Suite("対応待ちの一覧と巡回")
struct AttentionQueueTests {
    private let a = SessionID()
    private let b = SessionID()
    private let c = SessionID()
    private let d = SessionID()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("完了の未読・実行中・待機は対応待ちに含めない")
    func excludesNonAttentionStates() {
        let entries = AttentionQueue.ordered([
            (id: a, state: .doneUnread, since: t0),
            (id: b, state: .running, since: t0),
            (id: c, state: .idle, since: t0),
            (id: d, state: .error, since: t0),
        ])
        #expect(entries.map(\.id) == [d])
        #expect(entries.first?.kind == .error)
    }

    @Test("待ち時間の長い順（起点の古い順）に並べ、起点の無いものは末尾に置く")
    func ordersByLongestWait() {
        let entries = AttentionQueue.ordered([
            (id: a, state: .approval, since: t0.addingTimeInterval(180)),
            (id: b, state: .question, since: nil),
            (id: c, state: .error, since: t0),
            (id: d, state: .approval, since: t0.addingTimeInterval(60)),
        ])
        #expect(entries.map(\.id) == [c, d, a, b])
    }

    @Test("⌘J は一覧の順に次へ進み、末尾の次は先頭へ戻る")
    func nextCyclesInListOrder() {
        let entries = AttentionQueue.ordered([
            (id: a, state: .approval, since: t0),
            (id: b, state: .question, since: t0.addingTimeInterval(60)),
        ])
        #expect(AttentionQueue.next(after: a, in: entries) == b)
        #expect(AttentionQueue.next(after: b, in: entries) == a)
    }

    @Test("今のセッションが対応待ちでなければ先頭へ、対応待ちが無ければどこへも進まない")
    func nextFromOutsideStartsAtFirst() {
        let entries = AttentionQueue.ordered([(id: a, state: .approval, since: t0)])
        #expect(AttentionQueue.next(after: c, in: entries) == a)
        #expect(AttentionQueue.next(after: nil, in: entries) == a)
        #expect(AttentionQueue.next(after: a, in: []) == nil)
    }
}

@Suite("ツールバーの幅の段階")
struct ToolbarDensityTests {
    @Test("1280pt 以上は全要素、960pt 以上は短縮、それ未満は最小")
    func thresholds() {
        #expect(ToolbarDensity.forWindowWidth(1280) == .full)
        #expect(ToolbarDensity.forWindowWidth(1279) == .compact)
        #expect(ToolbarDensity.forWindowWidth(960) == .compact)
        #expect(ToolbarDensity.forWindowWidth(959) == .minimal)
    }
}

@Suite("Dock badge label")
struct DockBadgeLabelTests {
    @Test func hidesAtZero_showsTheCount_andCapsAt99Plus() {
        #expect(DockBadge.label(count: 0) == nil)
        #expect(DockBadge.label(count: 1) == "1")
        #expect(DockBadge.label(count: 99) == "99")
        #expect(DockBadge.label(count: 100) == "99+")
    }
}
