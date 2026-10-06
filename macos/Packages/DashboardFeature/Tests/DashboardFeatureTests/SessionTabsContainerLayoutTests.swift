import AppKit
import AgentDomain
import SwiftUI
import PTYKit
import Testing
@testable import DashboardFeature

@MainActor
struct SessionTabsContainerLayoutTests {
    // AppKit の端末（NSView）は SwiftUI の overlay より前面に出る（ADR 0136）。
    // 端末を .overlay で重ねると、上段のタブ列が端末に隠れて押せなくなる。
    @Test("共通ターミナルは上段のタブ列の下に置かれ、タブ列を覆わない")
    func commonTerminalDoesNotCoverTabBar() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let pty = MockPTYManager()
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(pty: pty, hookStream: hookStream))
        let router = AppRouter()
        router.commonTerminalSelected = true
        let controller = UserTerminalController(
            pty: pty, shellPath: "/bin/sh", workingDirectory: "/tmp", environment: ["PATH": "/usr/bin:/bin"]
        )
        let panel = TerminalPanelSession(controller: controller)
        let container = SessionTabsContainer(
            viewModel: dashboard, router: router, terminals: nil, commonTerminal: panel, simulatorHub: nil,
            editorPanel: EditorPanelCoordinator(), files: FileTabDocuments(), agentConsoleWindowID: nil
        ) { Color.clear }
        let host = NSHostingView(rootView: container.frame(width: 800, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()

        let terminal = panel.terminalCoordinator.hostingView
        #expect(terminal.isDescendant(of: host))
        let frame = host.convert(terminal.bounds, from: terminal)
        // タブ列は上端にある。端末はその下だけを占める。
        #expect(frame.height < host.bounds.height)
        let topY: CGFloat = host.isFlipped ? 4 : host.bounds.height - 4
        let tabBarHit = host.hitTest(host.convert(NSPoint(x: 4, y: topY), to: host.superview))
        #expect(tabBarHit?.isDescendant(of: terminal) != true)
        // 対照: 端末の中央は端末が受ける。
        let center = host.convert(NSPoint(x: frame.midX, y: frame.midY), to: host.superview)
        #expect(host.hitTest(center)?.isDescendant(of: terminal) == true)
        await controller.shutdown()
    }
}
