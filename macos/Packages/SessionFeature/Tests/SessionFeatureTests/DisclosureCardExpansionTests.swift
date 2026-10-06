// DisclosureCard は折りたたみ中は本文を描画せず、展開すると AgentMessageBody の本文を出す。
// 壊れると: 初期状態で本文が見えてしまう／展開しても本文が出ない／展開中の本文差し替えが表示に反映されない。

import AppKit
import DesignSystem
import Observation
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("DisclosureCard expansion", .serialized)
@MainActor
struct DisclosureCardExpansionTests {
    @Test("折りたたみ中は本文が無く、展開すると出て、同じ長さの本文差し替えにも追従する")
    func 展開で本文が出て差し替えに追従する() {
        let model = ProbeModel(text: "初期は有効な本文")
        let host = NSHostingView(rootView: DisclosureProbe(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil }

        settle(host)
        #expect(!viewTexts(in: host).contains { $0.contains("有効") })

        model.expansionRequest += 1
        settle(host)
        #expect(viewTexts(in: host).contains { $0.contains("有効") })

        model.text = String(repeating: "あ", count: model.text.count)
        settle(host)
        #expect(viewTexts(in: host).contains { $0.contains("あああ") })
        #expect(!viewTexts(in: host).contains { $0.contains("有効") })
    }
}

@Observable
@MainActor
private final class ProbeModel {
    var text: String
    var expansionRequest = 0
    init(text: String) { self.text = text }
}

private struct DisclosureProbe: View {
    @Bindable var model: ProbeModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureCard(isExpanded: $isExpanded, title: "思考の詳細", subtitle: nil) {
            AgentMessageBody(text: model.text, bodyColor: DSColor.chatTextSecondary)
        }
        .onChange(of: model.expansionRequest) { _, _ in isExpanded.toggle() }
    }
}

@MainActor
private func settle(_ host: NSView) {
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
    host.layoutSubtreeIfNeeded()
}

@MainActor
private func viewTexts(in root: NSView) -> [String] {
    var texts: [String] = []
    func visit(_ view: NSView) {
        if let field = view as? NSTextField, !field.stringValue.isEmpty { texts.append(field.stringValue) }
        if let textView = view as? NSTextView, !textView.string.isEmpty { texts.append(textView.string) }
        view.subviews.forEach(visit)
    }
    visit(root)
    return texts
}
