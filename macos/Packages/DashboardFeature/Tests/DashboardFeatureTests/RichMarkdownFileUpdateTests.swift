import AppKit
import SwiftUI
import DesignSystem
import Testing
import SessionFeature
@testable import DashboardFeature

extension ThemeRenderingTests {
    @Suite("ファイルのマークダウン表示の更新")
    @MainActor
    struct RichMarkdownFileUpdateTests {
        @Test
        func unchangedMarkdownOpensLinksWithTheLatestHandler() async throws {
            let app = NSApplication.shared
            let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
            let previousAccessibility = app.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: attribute.rawValue)?.takeUnretainedValue()
            app.accessibilitySetValue(true, forAttribute: attribute)
            defer { app.accessibilitySetValue(previousAccessibility, forAttribute: attribute) }
            var opened: [String] = []
            let document = FileTabDocument(path: "document.md", root: "/")
            document.draft = "前文 [案内](linked.md) 後文\n"
            let host = NSHostingView(rootView: FileTabUndoScope(document: document) {
                MarkdownBlockEditor(document: document, openURL: {
                    opened.append("old \($0.absoluteString)"); return .handled
                })
            })
            let window = makeWindow(host: host)
            defer { window.contentView = nil; window.close() }
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                return linkFrame(in: host, text: "案内") != nil
            }

            host.rootView = FileTabUndoScope(document: document) {
                MarkdownBlockEditor(document: document, openURL: {
                    opened.append("new \($0.absoluteString)"); return .handled
                })
            }
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                return linkFrame(in: host, text: "案内") != nil
            }
            let frame = try #require(linkFrame(in: host, text: "案内"))
            let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            try click(point, in: window)
            try await waitUntil { !opened.isEmpty }

            #expect(opened == ["new linked.md"])
            #expect(document.activeBlockEdit == nil)
        }

        @Test
        func sourceAndThemeUpdatesAppearInTheExistingDocument() async throws {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: ThemeStore.themeKey)
            defer {
                if let saved { defaults.set(saved, forKey: ThemeStore.themeKey) }
                else { defaults.removeObject(forKey: ThemeStore.themeKey) }
            }
            defaults.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
            let host = NSHostingView(rootView: RichMarkdownView(source: "変更前の本文", openURL: { _ in .handled }))
            let window = makeWindow(host: host)
            defer { window.contentView = nil; window.close() }
            _ = try await waitForField("変更前の本文", in: host)

            host.rootView = RichMarkdownView(source: "変更後の本文", openURL: { _ in .handled })
            let updated = try await waitForField("変更後の本文", in: host)
            let darkColor = try #require(updated.textColor)
            defaults.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
            try await waitUntil {
                host.layoutSubtreeIfNeeded()
                guard let color = textFields(in: host).first(where: { $0.stringValue == "変更後の本文" })?.textColor else { return false }
                return color != darkColor
            }

            let field = try #require(textFields(in: host).first { $0.stringValue == "変更後の本文" })
            #expect(!textFields(in: host).contains { $0.stringValue == "変更前の本文" })
            #expect(try #require(field.textColor) != darkColor)
        }

        private func makeWindow<Content: View>(host: NSHostingView<Content>) -> MarkdownTrackingWindow {
            host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
            let window = MarkdownTrackingWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderBack(nil)
            return window
        }

        private func textFields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
        }

        private func linkFrame(in view: NSView, text: String) -> NSRect? {
            var seen = Set<ObjectIdentifier>()
            func value(_ name: String, of object: NSObject) -> Any? {
                let selector = NSSelectorFromString(name)
                guard object.responds(to: selector) else { return nil }
                return object.perform(selector)?.takeUnretainedValue()
            }
            func visit(_ element: Any) -> NSRect? {
                guard let object = element as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return nil }
                let label = value("accessibilityValue", of: object) as? String ?? value("accessibilityLabel", of: object) as? String
                if label == text, value("accessibilityRole", of: object) as? String == NSAccessibility.Role.link.rawValue {
                    let frame = (object as AnyObject).accessibilityFrame()
                    if !frame.isEmpty { return frame }
                }
                for child in value("accessibilityChildren", of: object) as? [Any] ?? [] {
                    if let frame = visit(child) { return frame }
                }
                if let view = element as? NSView {
                    for child in view.subviews { if let frame = visit(child) { return frame } }
                }
                return nil
            }
            return visit(view)
        }

        private func waitForField(_ text: String, in host: NSView, sourceLocation: SourceLocation = #_sourceLocation) async throws -> NSTextField {
            try await waitUntil({
                host.layoutSubtreeIfNeeded()
                return textFields(in: host).contains { $0.stringValue == text }
            }, sourceLocation: sourceLocation)
            return try #require(textFields(in: host).first { $0.stringValue == text })
        }

        private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(condition(), sourceLocation: sourceLocation)
        }

        private func click(_ point: NSPoint, in window: NSWindow) throws {
            let timestamp = ProcessInfo.processInfo.systemUptime
            let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated().map { index, type in
                try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: timestamp + Double(index) * 0.02, windowNumber: window.windowNumber,
                    context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 0 ? 1 : 0))
            }
            try sendMarkdownMouseEvents(events, in: window)
        }
    }
}
