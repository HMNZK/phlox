import AppKit

public enum SimulatorKeyRouting {
    public enum Decision: Equatable, Sendable {
        case send
        case sendPressAndRelease
        case handleInPhlox
        case copyPasteboard
        case releaseFocus
    }

    /// sentKeyCodesは送信が済んだ押下だけ。物理の⌘Vは含めず、成功後は押下と解放を一組で送る。
    /// pbcopyの完了前はnil、失敗時はfalseを渡す。
    public static func route(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, down: Bool,
        sentKeyCodes: Set<UInt16>, pasteSucceeded: Bool? = nil
    ) -> Decision {
        if keyCode == 9, modifiers.contains(.command), let pasteSucceeded {
            return pasteSucceeded ? .sendPressAndRelease : .handleInPhlox
        }
        // 解放とキーリピートでは、後から変わった修飾キーで配送を止めない。
        if sentKeyCodes.contains(keyCode) { return .send }
        guard down else { return .handleInPhlox }
        if modifiers.contains(.command) {
            if keyCode == 53 { return .releaseFocus }
            if keyCode == 9 {
                return .copyPasteboard
            }
            return .handleInPhlox
        }
        if keyCode == 48 && modifiers.contains(.control) { return .handleInPhlox }
        return .send
    }
}
