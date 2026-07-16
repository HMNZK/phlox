import AppKit
import Testing
@testable import TerminalUI

/// TerminalHostingView の左 padding 制約の検証。
@MainActor
@Suite struct TerminalHostingViewTests {
    @Test func terminalViewLeadingConstraint_hasLeftPaddingOffset() throws {
        let terminalView = IMETerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        let hostingView = TerminalHostingView(terminalView: terminalView)

        let leadingConstraint = hostingView.constraints.first { constraint in
            constraint.firstItem as? NSObject === terminalView
                && constraint.firstAttribute == .leading
                && constraint.secondItem as? NSObject === hostingView
        }
        let constant = try #require(leadingConstraint?.constant)
        #expect(constant == TerminalHostingView.leftPadding)
        #expect(constant == 8)
    }

    @Test func nonLeadingConstraints_remainZeroOffset() {
        let terminalView = IMETerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))
        let hostingView = TerminalHostingView(terminalView: terminalView)

        let trailing = hostingView.constraints.first { constraint in
            constraint.firstItem as? NSObject === terminalView && constraint.firstAttribute == .trailing
        }
        let top = hostingView.constraints.first { constraint in
            constraint.firstItem as? NSObject === terminalView && constraint.firstAttribute == .top
        }
        let bottom = hostingView.constraints.first { constraint in
            constraint.firstItem as? NSObject === terminalView && constraint.firstAttribute == .bottom
        }

        #expect(trailing?.constant == 0)
        #expect(top?.constant == 0)
        #expect(bottom?.constant == 0)
    }
}
