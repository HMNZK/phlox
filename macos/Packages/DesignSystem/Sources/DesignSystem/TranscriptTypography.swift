import SwiftUI

/// トランスクリプト本文・処理見出し・補助情報の文字と間隔の正本。
/// 設定保存・I/O・時計・ViewModel に依存せず、受け取った有効倍率を一度だけ掛ける。
public enum TranscriptTypography {
    public enum Role: CaseIterable, Equatable, Hashable, Sendable {
        case body
        case bodyStrong
        case heading1
        case heading2
        case heading3
        case heading4
        case heading5
        case heading6
        case processSummary
        case metadata
        case metadataStrong
        case code
        case codeMetadata
        case inlineCode
    }

    public struct Style: Equatable, Sendable {
        public var baseSize: CGFloat
        public var weight: Weight
        public var design: Design
        public var ink: Ink

        public enum Weight: Equatable, Sendable {
            case regular
            case medium
            case semibold
            case bold
        }

        public enum Design: Equatable, Sendable {
            case system
            case monospaced
        }

        public enum Ink: Equatable, Sendable {
            case primary
            case secondary
            case tool
            case accent
        }
    }

    public enum BlockRole: Equatable, Sendable {
        case user
        case answer
        case process
        case auxiliary
    }

    public static let withinAnswer: CGFloat = DSSpacing.s
    public static let betweenAnswers: CGFloat = DSSpacing.l
    public static let majorSection: CGFloat = DSSpacing.xl
    public static let metadataGap: CGFloat = DSSpacing.xs
    public static let textLineSpacing: CGFloat = DSSpacing.xs
    public static let cardHorizontalInset: CGFloat = DSSpacing.m
    public static let cardVerticalInset: CGFloat = DSSpacing.s
    public static let codeContentInset: CGFloat = DSSpacing.m
    public static let transcriptHorizontalInset: CGFloat = DSSpacing.l
    public static let transcriptVerticalInset: CGFloat = DSSpacing.m

    public static func style(for role: Role) -> Style {
        switch role {
        case .body:
            Style(baseSize: 15, weight: .regular, design: .system, ink: .primary)
        case .bodyStrong:
            Style(baseSize: 15, weight: .semibold, design: .system, ink: .primary)
        case .heading1:
            Style(baseSize: 26, weight: .bold, design: .system, ink: .primary)
        case .heading2:
            Style(baseSize: 19, weight: .bold, design: .system, ink: .primary)
        case .heading3:
            Style(baseSize: 16, weight: .semibold, design: .system, ink: .primary)
        case .heading4:
            Style(baseSize: 15, weight: .semibold, design: .system, ink: .primary)
        case .heading5:
            Style(baseSize: 15, weight: .semibold, design: .system, ink: .primary)
        case .heading6:
            Style(baseSize: 15, weight: .semibold, design: .system, ink: .primary)
        case .processSummary:
            Style(baseSize: 15, weight: .semibold, design: .system, ink: .tool)
        case .metadata:
            Style(baseSize: 10, weight: .regular, design: .system, ink: .secondary)
        case .metadataStrong:
            Style(baseSize: 10, weight: .medium, design: .system, ink: .secondary)
        case .code:
            Style(baseSize: 13, weight: .regular, design: .monospaced, ink: .primary)
        case .codeMetadata:
            Style(baseSize: 10, weight: .regular, design: .monospaced, ink: .secondary)
        case .inlineCode:
            Style(baseSize: 13.5, weight: .regular, design: .monospaced, ink: .accent)
        }
    }

    public static func pointSize(for role: Role, scale: CGFloat) -> CGFloat {
        style(for: role).baseSize * scale
    }

    public static func font(for role: Role, scale: CGFloat) -> Font {
        let resolved = style(for: role)
        let weight: Font.Weight
        switch resolved.weight {
        case .regular:
            weight = .regular
        case .medium:
            weight = .medium
        case .semibold:
            weight = .semibold
        case .bold:
            weight = .bold
        }
        let design: Font.Design
        switch resolved.design {
        case .system:
            design = .default
        case .monospaced:
            design = .monospaced
        }
        return .system(size: pointSize(for: role, scale: scale), weight: weight, design: design)
    }

    public static func color(for role: Role) -> Color {
        switch style(for: role).ink {
        case .primary:
            DSColor.chatTextPrimary
        case .secondary:
            DSColor.chatTextSecondary
        case .tool:
            DSColor.chatToolCallText
        case .accent:
            DSColor.chatAccent
        }
    }

    public static func gap(after: BlockRole?, before: BlockRole) -> CGFloat {
        switch (after, before) {
        case (nil, _):
            0
        case (_, .user):
            majorSection
        case (.user, _):
            betweenAnswers
        case (.answer, .answer), (.answer, .process), (.answer, .auxiliary):
            withinAnswer
        case (.process, .answer), (.auxiliary, .answer):
            betweenAnswers
        case (.process, .process), (.process, .auxiliary), (.auxiliary, .process), (.auxiliary, .auxiliary):
            withinAnswer
        }
    }
}
