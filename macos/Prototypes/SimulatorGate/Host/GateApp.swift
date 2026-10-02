import SwiftUI

@main
enum GateApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = GateDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class GateDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 402, height: 914),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "シミュレーター関門"
        window.contentView = NSHostingView(rootView: GateView())
        window.center()
        window.orderFront(nil)
        self.window = window
    }
}

struct GateView: NSViewRepresentable {
    func makeNSView(context: Context) -> GateHost { GateHost() }
    func updateNSView(_ nsView: GateHost, context: Context) {}
}
