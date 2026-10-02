import AppKit
import Testing
@testable import SimulatorBridgeKit

struct SimulatorKeyRoutingTests {
    @Test func 押下後にCommandを押しても解放を送る() {
        #expect(route(0, [], true, []) == .send)
        #expect(route(55, .command, true, [0]) == .handleInPhlox)
        #expect(route(0, .command, false, [0]) == .send)
        #expect(route(55, [], false, []) == .handleInPhlox)
    }

    @Test func Command付きの新規押下だけを除外する() {
        #expect(route(0, .command, true, []) == .handleInPhlox)
        #expect(route(0, .command, true, [0]) == .send)
        #expect(route(0, [], false, []) == .handleInPhlox)
        #expect(route(56, .shift, true, []) == .send)
        #expect(route(56, .command, false, [56]) == .send)
    }

    @Test func 貼り付けはコピー成功後だけ送る() {
        #expect(route(9, .command, true, []) == .copyPasteboard)
        #expect(SimulatorKeyRouting.route(keyCode: 9, modifiers: .command, down: true,
                                         sentKeyCodes: [], pasteSucceeded: false) == .handleInPhlox)
        #expect(SimulatorKeyRouting.route(keyCode: 9, modifiers: .command, down: true,
                                         sentKeyCodes: [], pasteSucceeded: true) == .sendPressAndRelease)
        #expect(route(9, [], false, [9]) == .send)
        // 物理のVは送信済みにしないため、その解放も端末へ送らない。
        #expect(route(9, .command, false, []) == .handleInPhlox)
    }

    @Test(arguments: [true, false])
    func 貼り付け完了前にVを離しても端末にVが押されたまま残らない(down: Bool) {
        var sent: Set<UInt16> = []
        var pressed: Set<UInt16> = []
        var events: [Bool] = []
        func feed(_ down: Bool, paste: Bool? = nil) {
            switch SimulatorKeyRouting.route(keyCode: 9, modifiers: .command, down: down,
                                             sentKeyCodes: sent, pasteSucceeded: paste) {
            case .send:
                events.append(down)
                if down { sent.insert(9); pressed.insert(9) }
                else { sent.remove(9); pressed.remove(9) }
            case .sendPressAndRelease:
                events += [true, false]
                pressed.insert(9)
                pressed.remove(9)
            default: break
            }
        }
        feed(true)
        feed(false)
        feed(down, paste: true)
        #expect(events == [true, false])
        #expect(pressed.isEmpty)
        #expect(sent.isEmpty)
    }

    @Test func 子タブ巡回はPhloxで扱う() {
        #expect(route(48, .control, true, []) == .handleInPhlox)
        #expect(route(48, [.control, .shift], true, []) == .handleInPhlox)
        #expect(route(48, .control, false, [48]) == .send)
    }

    @Test func CommandEscで解除し通常のEscとTabは送る() {
        #expect(route(53, .command, true, []) == .releaseFocus)
        #expect(route(53, [], true, []) == .send)
        #expect(route(48, [], true, []) == .send)
        #expect(route(53, .command, false, [53]) == .send)
    }

    private func route(_ key: UInt16, _ modifiers: NSEvent.ModifierFlags, _ down: Bool,
                       _ sent: Set<UInt16>) -> SimulatorKeyRouting.Decision {
        SimulatorKeyRouting.route(keyCode: key, modifiers: modifiers, down: down, sentKeyCodes: sent)
    }
}
