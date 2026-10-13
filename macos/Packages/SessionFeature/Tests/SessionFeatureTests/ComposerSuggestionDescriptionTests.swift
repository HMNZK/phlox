import AppKit
import QuartzCore
import SwiftUI
import Testing
import DesignSystem
@testable import SessionFeature

@Suite @MainActor
struct ComposerSuggestionDescriptionTests {
    private let description = "先頭から最後まで読める説明です。コマンド名と出どころは固定し、この長い説明だけが一定の速さで進みます。末尾です。"

    @Test("流す説明文は選択行の面の上の色（accentOnFill）で、テーマを替えると描き直す")
    func scrollingDescriptionUsesAccentOnFill() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous { defaults.set(previous, forKey: ThemeStore.themeKey) } else { defaults.removeObject(forKey: ThemeStore.themeKey) }
        }
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        func ink() -> NSColor? {
            ((view.textLayer.string as? NSAttributedString)?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
                .usingColorSpace(.sRGB)
        }
        defaults.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        view.setText(description)
        let dark = try #require(ink())
        #expect(dark == NSColor(DSColor.accentOnFill).usingColorSpace(.sRGB))
        #expect(dark.brightnessComponent < 0.5, "ダークの白い面に白い文字を載せない")

        defaults.set(AppTheme.phloxLight.id, forKey: ThemeStore.themeKey)
        view.setText(description)
        #expect(try #require(ink()).brightnessComponent > 0.5)
    }

    @Test func overflowingDescriptionReachesTheEndAndRepeatsWithReadingPauses() throws {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        let window = mount(view)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let animation = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey) as? CAKeyframeAnimation)
        let values = try #require(animation.values as? [NSNumber]).map { CGFloat(truncating: $0) }
        let times = try #require(animation.keyTimes?.map(\.doubleValue))
        #expect(values.count == 4 && times.count == 4)
        #expect(values[0] == 0 && values[1] == 0)
        #expect(abs(view.textLayer.frame.maxX + values[2] - view.bounds.maxX) < 0.01)
        #expect(values[2] == values[3])
        #expect(abs(times[1] * animation.duration - 1.5) < 0.01)
        #expect(abs((1 - times[2]) * animation.duration - 1.5) < 0.01)
        #expect(abs(-values[2] / ((times[2] - times[1]) * animation.duration) - 30) < 0.01)
        #expect(times.first == 0 && times.last == 1)
        #expect(animation.calculationMode == .linear)
        #expect(animation.repeatCount == .infinity)
        #expect(!animation.autoreverses)
        #expect(view.layer?.masksToBounds == true)
    }

    @Test func shortTextAndZeroWidthDoNotAnimate() {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText("短い説明")
        let window = mount(view)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
        view.setText(description)
        view.frame.size.width = 0
        view.layout()
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
    }

    @Test func multilineDescriptionsShowTheLaterLinesToo() {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 20, height: 16))
        view.setText("先頭の説明\n途中の説明\n最後の説明")
        let window = mount(view, width: 20)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        #expect((view.textLayer.string as? NSAttributedString)?.string == "先頭の説明 途中の説明 最後の説明")
        #expect(view.textLayer.animationKeys()?.count == 1)
    }

    @Test func repeatedUpdatesKeepTheExistingAnimation() throws {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        let window = mount(view)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let animation = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey)?.copy() as? CAAnimation)
        // 既存のアニメーションを識別し、通常の再描画で開始し直さないことを検査する。
        animation.setValue("existing", forKey: "testIdentity")
        view.textLayer.add(animation, forKey: SuggestionDescriptionScrollView.animationKey)
        for _ in 0..<100 {
            view.setText(description)
            view.layout()
        }
        #expect(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey)?.value(forKey: "testIdentity") as? String == "existing")
    }

    @Test func textRasterIncludesGlyphsBeyondTheInitialViewport() async throws {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        let window = mount(view)
        defer { window.close() }
        window.orderFront(nil)
        try await settle(view)
        CATransaction.flush()
        try await settle(view)
        let layer = view.textLayer
        let width = Int(ceil(layer.bounds.width))
        let height = Int(ceil(layer.bounds.height))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        layer.render(in: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let rightHalfContainsText = (0..<height).contains { y in
            (width / 2..<width).contains { x in pixels[y * context.bytesPerRow + x * 4 + 3] > 0 }
        }
        #expect(width / 2 > Int(view.bounds.width))
        #expect(rightHalfContainsText, "初期表示範囲の外にある説明の文字が描画されていません")
    }

    @Test func coreAnimationMovesOnlyTheTextAndReturnsToTheStart() async throws {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        let window = mount(view)
        defer { window.close() }
        // 画面外のウィンドウで描画する。フォーカスは移動させない。
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        let layer = view.textLayer
        let animation = try #require(layer.animation(forKey: SuggestionDescriptionScrollView.animationKey)?.copy() as? CAKeyframeAnimation)
        let values = try #require(animation.values as? [NSNumber]).map { CGFloat(truncating: $0) }
        let times = try #require(animation.keyTimes?.map(\.doubleValue))
        let frame = view.textLayer.frame
        layer.speed = 0
        animation.beginTime = 1
        layer.add(animation, forKey: SuggestionDescriptionScrollView.animationKey)
        for (elapsed, expected) in [
            (0.75, CGFloat.zero),
            ((times[1] + times[2]) / 2 * animation.duration, values[2] / 2),
            (animation.duration - 0.75, values[2]),
            (animation.duration + 0.75, CGFloat.zero),
        ] {
            layer.timeOffset = 1 + elapsed
            CATransaction.flush()
            try await settle(view)
            let presentation = try #require(layer.presentation())
            #expect(abs(presentation.transform.m41 - expected) < 1)
            #expect(view.textLayer.frame == frame)
            #expect(view.bounds.width == 120)
        }
    }

    @Test func resizingAndChangingTextRecalculateTravel() throws {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        let window = mount(view)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let first = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey))
        view.frame.size.width = 180
        view.layout()
        let resized = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey))
        #expect(abs(first.duration - resized.duration - 2) < 0.01)
        view.setText("短い説明")
        view.layout()
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
        view.setText(description + "説明を変更しました。")
        view.layout()
        let changed = try #require(view.textLayer.animation(forKey: SuggestionDescriptionScrollView.animationKey))
        #expect(changed.duration > resized.duration)
        view.frame.size.width = view.textLayer.frame.width + 1
        view.layout()
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
    }

    @Test func hiddenAndDetachedViewsStopAnimating() {
        let view = SuggestionDescriptionScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        view.setText(description)
        view.layout()
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
        let window = mount(view)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        #expect(view.textLayer.animationKeys()?.count == 1)
        view.isHidden = true
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
        view.isHidden = false
        view.layoutSubtreeIfNeeded()
        #expect(view.textLayer.animationKeys()?.count == 1)
        window.contentView = nil
        #expect(view.textLayer.animationKeys()?.isEmpty != false)
    }

    @Test func popupAnimatesOnlyTheSelectedDescription() async throws {
        let controller = makeController()
        let host = NSHostingView(rootView: ComposerSuggestionPopup(controller: controller, onAccept: { _ in }))
        let window = mount(host, width: 460, height: 180)
        defer { window.close() }
        try await settle(host)
        var views = scrollViews(in: host)
        #expect(views.count == 1)
        #expect((views.first?.textLayer.string as? NSAttributedString)?.string == description)
        #expect(views.first?.textLayer.animationKeys()?.count == 1)
        let previous = try #require(views.first)
        controller.select(1)
        try await settle(host)
        views = scrollViews(in: host)
        #expect(views.count == 1)
        #expect((views.first?.textLayer.string as? NSAttributedString)?.string == description + "別の候補の末尾です。")
        #expect(previous.textLayer.animationKeys()?.isEmpty != false)
        // Buttonは名前・全文の説明・出どころを1つのラベルへまとめる。ネイティブ描画の重複ラベルに依存しない。
        #expect(accessibilityText(in: host).contains("/review, " + description + "別の候補の末尾です。, .claude/skills"))
        let selected = try #require(views.first)
        controller.dismiss()
        try await settle(host)
        #expect(scrollViews(in: host).isEmpty)
        #expect(selected.textLayer.animationKeys()?.isEmpty != false)
    }

    @Test func reduceMotionDisablesScrollingAndKeepsTheFullAccessibilityLabel() async throws {
        let host = NSHostingView(rootView: ComposerSuggestionDescription(text: description, isSelected: true, reduceMotion: false))
        let window = mount(host)
        defer { window.close() }
        try await settle(host)
        #expect(scrollViews(in: host).count == 1)
        host.rootView = ComposerSuggestionDescription(text: description, isSelected: true, reduceMotion: true)
        try await settle(host)
        #expect(scrollViews(in: host).isEmpty)
        #expect(accessibilityText(in: host).contains(description))
    }

    @Test func fileSuggestionsDoNotCreateScrollingViews() async throws {
        let controller = ComposerSuggestionController(slashProvider: { [] }, fileProvider: { _ in [
            SuggestionCandidate(title: "file.swift", insertionText: "@file.swift", subtitle: description, kind: .fileReference),
        ] })
        controller.update(text: "@", cursorUTF16: 1)
        let host = NSHostingView(rootView: ComposerSuggestionPopup(controller: controller, onAccept: { _ in }))
        let window = mount(host, width: 460, height: 120)
        defer { window.close() }
        try await settle(host)
        #expect(scrollViews(in: host).isEmpty)
    }

    private func makeController() -> ComposerSuggestionController {
        let controller = ComposerSuggestionController(slashProvider: { [
            SuggestionCandidate(title: "/skill-creator", insertionText: "/skill-creator", subtitle: description, kind: .slashCommand, origin: .skills),
            SuggestionCandidate(title: "/review", insertionText: "/review", subtitle: description + "別の候補の末尾です。", kind: .slashCommand, origin: .skills),
        ] }, fileProvider: { _ in [] })
        controller.update(text: "/", cursorUTF16: 1)
        return controller
    }

    private func mount(_ view: NSView, width: CGFloat = 120, height: CGFloat = 16) -> NSWindow {
        _ = NSApplication.shared
        // このテストプロセスだけでSwiftUIのアクセシビリティ木を作る。
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
    }

    private func scrollViews(in view: NSView) -> [SuggestionDescriptionScrollView] {
        (view as? SuggestionDescriptionScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func accessibilityText(in view: NSView) -> Set<String> {
        var result = Set<String>()
        var seen = Set<ObjectIdentifier>()
        func visit(_ element: Any) {
            let object = element as AnyObject
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            for value in [object.accessibilityLabel(), object.accessibilityValue()] {
                if let text = value { result.insert(text) }
            }
            object.accessibilityChildren()?.forEach(visit)
            (element as? NSView)?.subviews.forEach(visit)
        }
        visit(view)
        return result
    }
}
