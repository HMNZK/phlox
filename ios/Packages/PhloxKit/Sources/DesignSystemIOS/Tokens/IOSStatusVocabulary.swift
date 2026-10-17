import SwiftUI
import AgentDomain
import DesignSystem

public enum IOSStatusWeight: Equatable, Sendable {
    case regular
    case medium
    case semibold

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}

public struct IOSStatusPresentation: Equatable {
    public let label: String?
    public let color: Color?
    public let weight: IOSStatusWeight?

    public var isVisible: Bool { label != nil }

    public init(label: String?, color: Color?, weight: IOSStatusWeight?) {
        self.label = label
        self.color = color
        self.weight = weight
    }
}

/// アプリ内セッション状態の表示語・色・太さを一か所で決める。
public enum IOSStatusVocabulary {
    public static func presentation(
        for status: SessionStatus,
        locale: Locale = .current
    ) -> IOSStatusPresentation {
        switch status {
        case .idle:
            IOSStatusPresentation(label: nil, color: nil, weight: nil)
        case .starting:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.text.tertiary,
                weight: .regular
            )
        case .running:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.text.secondary,
                weight: .medium
            )
        case .awaitingApproval:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.status.approval,
                weight: .semibold
            )
        case .awaitingUserQuestion:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.status.question,
                weight: .semibold
            )
        case .error:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.status.error,
                weight: .semibold
            )
        case .completed:
            IOSStatusPresentation(
                label: localizedLabel(for: status, locale: locale),
                color: IOSColor.text.tertiary,
                weight: .regular
            )
        }
    }

    private static func localizedLabel(for status: SessionStatus, locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "ja" {
            return StatusBadge.label(for: status)
        }
        if case .completed = status {
            return "done"
        }
        return StatusBadge.englishLabel(for: status)
    }
}
