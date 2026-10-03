import AppKit
import DashboardFeature

@main
@MainActor
final class InputHarness: NSObject, NSApplicationDelegate {
    private let connection = SimulatorDisplayConnection()
    private let screen = SimulatorScreenNSView()
    private var window: NSWindow?
    private var pasteboardContents: [[NSPasteboard.PasteboardType: Data]]?

    static func main() {
        let app = NSApplication.shared
        let delegate = InputHarness()
        app.delegate = delegate
        app.setActivationPolicy(ProcessInfo.processInfo.arguments.contains("--background-tap") ? .prohibited : .regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        guard let udid = environment["INPUT_UDID"],
              let width = Double(environment["INPUT_WIDTH"] ?? ""),
              let height = Double(environment["INPUT_HEIGHT"] ?? "") else { finish("端末の指定がありません", status: 1); return }
        let background = ProcessInfo.processInfo.arguments.contains("--background-tap")
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let window = background
            ? BackgroundInputWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
            : NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "入力確認（本番 view・本番 XPC）"
        window.contentView = screen
        self.window = window
        screen.connection = connection
        if !background {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        window.makeFirstResponder(screen)
        connection.attach(udid: udid)
        Task { await exercise() }
    }

    private func exercise() async {
        do {
            for _ in 0..<300 {
                if let info = connection.displayInfo { screen.update(info); break }
                if let reason = connection.reason { finish(reason, status: 1); return }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard connection.displayInfo != nil else { finish("表示接続の期限切れ", status: 1); return }
            try await Task.sleep(for: .seconds(1))
            try await tap(x: 150, y: 160)
            if ProcessInfo.processInfo.arguments.contains("--background-tap") {
                try await Task.sleep(for: .seconds(1))
                connection.disconnect()
                finish("バックグラウンドのタップを配送しました。到達は観測アプリの記録で確認します", status: 0)
                return
            }
            try await drag(x: 60, y: 250, toX: 220, toY: 250)
            // スクロールは通常のホイールイベントを本番 view に渡す。
            try await measuredScroll(name: "ホイール100pt", delta: -100)
            try await measuredScroll(name: "トラックパッド100pt", delta: -100, phased: true)
            try await measuredScroll(name: "ボタン上の小量ホイール", delta: -1, y: 160)
            try await measuredScroll(name: "ボタン上の小量トラックパッド", delta: -1, phased: true, y: 160)
            // 短い間隔のホイール入力を接触で中断。保留中のスクロールが再開しないことを全接触記録で確認する。
            for _ in 0..<3 {
                scroll(delta: -20)
                try await Task.sleep(for: .milliseconds(20))
            }
            try await tap(x: 150, y: 160)
            try await Task.sleep(for: .milliseconds(200))
            try await tap(x: 150, y: 475)
            key(.keyDown, code: 0, text: "a")
            key(.keyUp, code: 0, text: "a")
            let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2)
            key(.flagsChanged, code: 56, text: "", flags: leftShift)
            key(.keyDown, code: 11, text: "B", flags: .shift)
            key(.keyUp, code: 11, text: "B", flags: .shift)
            key(.flagsChanged, code: 56, text: "")
            pasteboardContents = NSPasteboard.general.pasteboardItems?.map { item in
                Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
            } ?? []
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("貼付", forType: .string)
            key(.keyDown, code: 9, text: "v", flags: .command)
            key(.keyUp, code: 9, text: "v", flags: .command)
            try await Task.sleep(for: .seconds(2))
            restorePasteboard()
            // フォーカス喪失による releaseAll 後、同じ領域で新しいドラッグができることを観測する。
            key(.keyDown, code: 8, text: "c")
            mouse(.leftMouseDown, x: 60, y: 250)
            mouse(.leftMouseDragged, x: 120, y: 250)
            try await Task.sleep(for: .milliseconds(200))
            window?.makeFirstResponder(nil)
            try await Task.sleep(for: .milliseconds(200))
            window?.makeFirstResponder(screen)
            try await drag(x: 60, y: 250, toX: 220, toY: 250)
            connection.sendHome()
            try await Task.sleep(for: .seconds(1))
            screen.stop()
            connection.disconnect()
            finish("入力配送を実行しました。成否は iOS 側の events.json で判定します", status: 0)
        } catch { finish("入力確認失敗: \(error)", status: 1) }
    }

    private func tap(x: CGFloat, y: CGFloat) async throws {
        try focusScreen()
        mouse(.leftMouseDown, x: x, y: y)
        try await Task.sleep(for: .milliseconds(100))
        mouse(.leftMouseUp, x: x, y: y)
        try await Task.sleep(for: .milliseconds(300))
    }

    private func drag(x: CGFloat, y: CGFloat, toX: CGFloat, toY: CGFloat) async throws {
        try focusScreen()
        mouse(.leftMouseDown, x: x, y: y)
        for step in 1...10 {
            try await Task.sleep(for: .milliseconds(30))
            mouse(.leftMouseDragged, x: x + (toX - x) * CGFloat(step) / 10, y: y + (toY - y) * CGFloat(step) / 10)
        }
        mouse(.leftMouseUp, x: toX, y: toY)
        try await Task.sleep(for: .milliseconds(300))
    }

    private func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) {
        let point = screen.convert(NSPoint(x: x, y: screen.bounds.height - y), to: nil)
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        switch type {
        case .leftMouseDown: screen.mouseDown(with: event)
        case .leftMouseDragged: screen.mouseDragged(with: event)
        default: screen.mouseUp(with: event)
        }
    }

    private func measuredScroll(name: String, delta: Int32, phased: Bool = false, y: CGFloat = 370) async throws {
        try focusScreen()
        let start = Date().timeIntervalSince1970
        if phased {
            scroll(delta: 0, phase: 1, y: y)
            for _ in 0..<5 {
                scroll(delta: delta / 5, phase: 2, y: y)
                try await Task.sleep(for: .milliseconds(40))
            }
            // 1pt の短いジェスチャーも確かめる。
            if abs(delta) < 5 { scroll(delta: delta, phase: 2, y: y) }
            scroll(delta: 0, phase: 4, y: y)
        } else { scroll(delta: delta, y: y) }
        try await Task.sleep(for: .seconds(1))
        let data = try JSONSerialization.data(withJSONObject: ["名前": name, "開始": start,
            "終了": Date().timeIntervalSince1970, "入力量": abs(delta)])
        print("検査区間:" + String(decoding: data, as: UTF8.self))
        fflush(stdout)
    }

    private func focusScreen() throws {
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(screen)
        guard window?.isKeyWindow == true, window?.firstResponder === screen else {
            throw NSError(domain: "入力確認", code: 1, userInfo: [NSLocalizedDescriptionKey: "確認用画面へフォーカスできません"])
        }
    }

    private func scroll(delta: Int32, phase: Int64 = 0, y: CGFloat = 370) {
        let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        let point = screen.convert(NSPoint(x: 150, y: screen.bounds.height - y), to: nil)
        // CGEvent から作る NSEvent は windowNumber が 0。上原点を戻して view のウィンドウ座標を渡す。
        scroll.location = NSPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
        screen.scrollWheel(with: NSEvent(cgEvent: scroll)!)
    }

    private func key(_ type: NSEvent.EventType, code: UInt16, text: String, flags: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window!.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                                    isARepeat: false, keyCode: code)!
        switch type {
        case .keyDown: screen.keyDown(with: event)
        case .keyUp: screen.keyUp(with: event)
        default: screen.flagsChanged(with: event)
        }
    }

    private func finish(_ message: String, status: Int32) {
        restorePasteboard()
        print(message)
        fflush(stdout)
        exit(status)
    }

    private func restorePasteboard() {
        guard let contents = pasteboardContents else { return }
        pasteboardContents = nil
        let items = contents.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items)
    }
}

/// OS のフォーカスを取得せず、本番ビューへ直接渡すイベントだけを検査する。
@MainActor private final class BackgroundInputWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
