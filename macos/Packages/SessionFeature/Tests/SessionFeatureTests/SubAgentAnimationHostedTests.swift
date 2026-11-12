import AppKit
import AgentDomain
import QuartzCore
import SwiftUI
import Testing
@testable import SessionFeature

@Suite("実行中サブエージェントの表示", .serialized) @MainActor
struct SubAgentAnimationHostedTests {
    @Test("実行中の依頼内容に文字アニメーションが付き、完了後は止まる")
    func runningDescriptionAnimatesAndCompletionStopsIt() async throws {
        let hosting = NSHostingView(rootView: row(status: .running, visible: true))
        let window = host(hosting)
        defer { window.close() }

        let running = await waitForAnimation(true, in: hosting)
        hosting.rootView = row(status: .completed, visible: true)
        let completed = await waitForAnimation(false, in: hosting)

        #expect(running, "実行中のサブエージェントの依頼内容にも文字の明るさの移動が必要")
        #expect(completed, "完了後に実行中の文字アニメーションを残さない")
    }

    @Test("表示中でないサブエージェント行はアニメーションを動かさない")
    func hidingAnActiveRowStopsItsAnimation() async throws {
        let hosting = NSHostingView(rootView: row(status: .running, visible: true))
        let window = host(hosting)
        defer { window.close() }

        let running = await waitForAnimation(true, in: hosting)
        hosting.rootView = row(status: .running, visible: false)
        let hidden = await waitForAnimation(false, in: hosting)

        #expect(running)
        #expect(hidden)
    }

    private func row(status: SubAgentStatus, visible: Bool) -> some View {
        let items: [ChatItem] = [
            .userMessage(id: "input", text: "変更を確認", timestamp: .distantPast, attachments: []),
            .subAgentMarker(id: "child", subagentType: "reviewer", description: "カードUIの差分をレビュー", status: status),
        ]
        let blocks = AgentStatusCardBuilder.build(items: items,
            liveState: .init(isProcessing: true, activityState: .thinking, hangAssessment: nil, isAwaitingReply: false))
        let action = blocks.compactMap { block -> AgentStatusAction? in
            guard case .statusCard(let card) = block, case .outside(let group)? = card.rows.first,
                case .action(let action)? = group.entries.first else { return nil }
            return action
        }.first!
        return AgentStatusActionRow(action: action, scale: 1, isTimelineVisible: visible)
            .environment(\.scenePhase, .active)
            .environment(\.locale, Locale(identifier: "ja"))
            .frame(width: 600, height: 30)
    }

    private func host<Content: View>(_ hosting: NSHostingView<Content>) -> NSWindow {
        _ = NSApplication.shared
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 40)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = hosting
        window.orderBack(nil)
        return window
    }

    private func waitForAnimation(_ expected: Bool, in hosting: NSView) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        repeat {
            hosting.layoutSubtreeIfNeeded()
            CATransaction.flush()
            if !hosting.subviews.isEmpty, hasRunningAnimation(hosting) == expected { return true }
            await Task.yield()
        } while ContinuousClock.now < deadline
        return false
    }

    private func hasRunningAnimation(_ view: NSView) -> Bool {
        hasRunningAnimation(view.layer) || view.subviews.contains(where: hasRunningAnimation)
    }

    private func hasRunningAnimation(_ layer: CALayer?) -> Bool {
        guard let layer, layer.speed != 0 else { return false }
        return (layer.animationKeys() ?? []).contains { key in
            layer.animation(forKey: key)?.repeatCount == .infinity
        } || (layer.sublayers ?? []).contains { hasRunningAnimation($0) }
    }
}
