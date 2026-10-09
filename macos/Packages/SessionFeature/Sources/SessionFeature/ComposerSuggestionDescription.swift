import AppKit
import DesignSystem
import QuartzCore
import SwiftUI

/// レイアウトと読み上げは静的なTextが担当し、選択中の描画だけを横送りする。
struct ComposerSuggestionDescription: View {
    let text: String
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        let scrolls = isSelected && !reduceMotion
        Text(verbatim: text)
            .font(DSFont.auxiliary)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            .overlay(alignment: .leading) {
                if scrolls {
                    NativeSuggestionDescription(text: text)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
            .help(Text(verbatim: text))
    }
}

private struct NativeSuggestionDescription: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> SuggestionDescriptionScrollView {
        SuggestionDescriptionScrollView()
    }

    func updateNSView(_ view: SuggestionDescriptionScrollView, context: Context) {
        view.setText(text)
    }

    static func dismantleNSView(_ view: SuggestionDescriptionScrollView, coordinator: ()) {
        view.stopScrolling()
    }
}

/// Core Animationに文字の平行移動を任せる。フレームごとのSwiftUI更新やタイマーは不要。
@MainActor
final class SuggestionDescriptionScrollView: NSView {
    static let animationKey = "descriptionScroll"
    static let readingPause: TimeInterval = 1.5
    static let pointsPerSecond: CGFloat = 30
    let label = NSTextField(labelWithString: "")
    private var text = ""
    private var textSize = NSSize.zero
    private var animatedDistance: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        label.font = .systemFont(ofSize: 12) // DSFont.auxiliary
        label.textColor = .white
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        setAccessibilityElement(false)
        label.setAccessibilityElement(false)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    func setText(_ text: String) {
        guard self.text != text else { return }
        self.text = text
        label.stringValue = text.components(separatedBy: .newlines).joined(separator: " ")
        textSize = label.intrinsicContentSize
        stopScrolling()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.frame = NSRect(x: 0, y: (bounds.height - textSize.height) / 2,
                             width: ceil(textSize.width), height: textSize.height)
        CATransaction.commit()
        let distance = max(0, ceil(textSize.width) - bounds.width)
        guard window != nil, !isHiddenOrHasHiddenAncestor, bounds.width > 0, distance > 0 else {
            stopScrolling()
            return
        }
        // 本文や幅が変わらなければ、選択行の再描画でも先頭へ戻さない。
        guard animatedDistance != distance || label.layer?.animation(forKey: Self.animationKey) == nil else { return }
        let travel = Double(distance / Self.pointsPerSecond)
        let duration = Self.readingPause * 2 + travel
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [NSNumber(value: 0), NSNumber(value: 0),
                            NSNumber(value: Double(-distance)), NSNumber(value: Double(-distance))]
        animation.keyTimes = [0, NSNumber(value: Self.readingPause / duration),
                              NSNumber(value: (Self.readingPause + travel) / duration), 1]
        animation.calculationMode = .linear
        animation.duration = duration
        animation.repeatCount = .infinity
        label.layer?.add(animation, forKey: Self.animationKey)
        animatedDistance = distance
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopScrolling() }
        else { needsLayout = true }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopScrolling()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        needsLayout = true
    }

    func stopScrolling() {
        label.layer?.removeAnimation(forKey: Self.animationKey)
        animatedDistance = nil
    }
}
