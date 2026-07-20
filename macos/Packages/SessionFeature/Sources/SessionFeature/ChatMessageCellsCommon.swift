import AppKit
import SwiftUI
import AgentDomain
import DesignSystem

struct AvatarMessageRow<Content: View>: View {
    let descriptor: AgentDescriptor
    let timestamp: Date
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.m) {
            AgentAvatar(descriptor: descriptor)
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                ChatTimestampText(timestamp: timestamp)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentAvatar: View {
    private static let iconSize: CGFloat = 24

    let descriptor: AgentDescriptor

    var body: some View {
        AgentBrandIcon(descriptor: descriptor, size: Self.iconSize)
            .accessibilityLabel(descriptor.displayName)
    }
}

struct ChatTimestampText: View {
    let timestamp: Date
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        if timestamp != .distantPast {
            Text(Self.formatter.string(from: timestamp))
                .font(ChatScaledFont.caption(scale: scale))
                .foregroundStyle(DSColor.chatTextSecondary)
                .monospacedDigit()
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

enum DisclosureStatus {
    case running
    case complete
}

struct DisclosureCard<Content: View>: View {
    @Binding var isExpanded: Bool
    let title: String
    let subtitle: String?
    let timestamp: Date
    let systemImage: String
    let accent: Color
    let status: DisclosureStatus
    @ViewBuilder let content: Content
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.leading, 22 + DSSpacing.s)
        } label: {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: DSIconSize.l, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(ChatScaledFont.captionStrong(scale: scale))
                        .foregroundStyle(DSColor.chatTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(ChatScaledFont.caption(scale: scale))
                            .foregroundStyle(DSColor.chatTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: DSSpacing.s)
                ChatTimestampText(timestamp: timestamp)
                StatusGlyph(status: status, accent: accent)
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }
}

private struct StatusGlyph: View {
    let status: DisclosureStatus
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        switch status {
        case .running:
            Group {
                if reduceMotion {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 3))
                } else {
                    DisclosureRunningSpinner(color: accent)
                }
            }
            .frame(width: 12, height: 12)
            .accessibilityLabel("Running")
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DSIconSize.l, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityLabel("Complete")
        }
    }
}

/// DesignSystem の `RunningSpinner` と同じ Core Animation 駆動。
/// モジュール外から `RunningSpinner` を import できないため、
/// repeat-forever を避ける実装パターンのみ同ファイルに持つ。
private struct DisclosureRunningSpinner: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> SpinnerView {
        let view = SpinnerView()
        view.update(color: NSColor(color).cgColor)
        return view
    }

    func updateNSView(_ nsView: SpinnerView, context: Context) {
        nsView.update(color: NSColor(color).cgColor)
    }

    final class SpinnerView: NSView {
        private let shape = CAShapeLayer()
        private static let arcKey = "phlox.disclosure.spinner.rotation"

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            configureShape()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize { NSSize(width: 11, height: 11) }

        private func configureShape() {
            shape.fillColor = NSColor.clear.cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            shape.strokeStart = 0
            shape.strokeEnd = 0.72
            shape.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(shape)
            addRotationAnimation()
        }

        private func addRotationAnimation() {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 0.8
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotation.isRemovedOnCompletion = false
            shape.add(rotation, forKey: Self.arcKey)
        }

        func update(color: CGColor) {
            shape.strokeColor = color
        }

        override func layout() {
            super.layout()
            let side: CGFloat = 11
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            shape.bounds = rect
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
            shape.path = CGPath(ellipseIn: rect, transform: nil)
        }
    }
}
