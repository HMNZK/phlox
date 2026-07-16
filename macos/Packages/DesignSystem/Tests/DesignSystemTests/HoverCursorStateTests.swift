import Testing
@testable import DesignSystem

@Suite struct HoverCursorStateTests {
    @Test func enabledHoverPushesAndLeavePops() {
        var state = HoverCursorState()
        #expect(state.update(hovering: true, isEnabled: true) == .push)
        #expect(state.update(hovering: false, isEnabled: true) == .pop)
    }

    /// B6 再現: disabled ボタンへのホバーでは push していないので、進入・離脱とも pop してはならない。
    @Test func disabledHoverNeverPushesNorPops() {
        var state = HoverCursorState()
        #expect(state.update(hovering: true, isEnabled: false) == .none)
        #expect(state.update(hovering: false, isEnabled: false) == .none)
    }

    /// ホバー中に disabled へ変わったら、push 済みの分だけ pop して対応を取る。
    @Test func becomingDisabledWhilePushedPopsOnce() {
        var state = HoverCursorState()
        #expect(state.update(hovering: true, isEnabled: true) == .push)
        #expect(state.update(hovering: true, isEnabled: false) == .pop)
        #expect(state.update(hovering: false, isEnabled: false) == .none)
    }

    @Test func repeatedHoverDoesNotDoublePush() {
        var state = HoverCursorState()
        #expect(state.update(hovering: true, isEnabled: true) == .push)
        #expect(state.update(hovering: true, isEnabled: true) == .none)
    }

    /// 進入イベントなしの離脱(onHover(false) が先に届くケース)でも pop しない。
    @Test func leaveWithoutEnterDoesNothing() {
        var state = HoverCursorState()
        #expect(state.update(hovering: false, isEnabled: true) == .none)
    }

    @Test func finishPopsOnlyWhenPushed() {
        var pushed = HoverCursorState()
        _ = pushed.update(hovering: true, isEnabled: true)
        #expect(pushed.finish() == .pop)
        // finish 後は押していないので、もう一度呼んでも pop しない。
        #expect(pushed.finish() == .none)

        var untouched = HoverCursorState()
        #expect(untouched.finish() == .none)
    }
}
