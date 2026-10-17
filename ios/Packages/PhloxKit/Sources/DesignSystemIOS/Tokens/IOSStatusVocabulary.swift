import SwiftUI
import AgentDomain
import DesignSystem
import PhloxCore

public enum IOSStatusWeight: Equatable, Sendable {
    case regular
    case medium
    case semibold

    public var fontWeight: Font.Weight {
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
        presentation(for: SessionDisplayState.resolve(status), locale: locale)
    }

    public static func presentation(
        for state: SessionDisplayState,
        locale: Locale = .current
    ) -> IOSStatusPresentation {
        switch state {
        case .idle:
            IOSStatusPresentation(label: nil, color: nil, weight: nil)
        case .starting:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.text.tertiary, weight: .regular)
        case .running:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.text.secondary, weight: .medium)
        case .approval:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.status.approval, weight: .semibold)
        case .question:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.status.question, weight: .semibold)
        case .error:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.status.error, weight: .semibold)
        case .stalled:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.status.stalled, weight: .semibold)
        case .doneUnread, .done:
            IOSStatusPresentation(label: state.localizedLabel(locale: locale), color: IOSColor.text.tertiary, weight: .regular)
        }
    }
}

public extension Session {
    /// Resolve list status with the shared DesignSystem rule used by macOS.
    var displayState: SessionDisplayState {
        SessionDisplayState.resolve(
            status,
            hasUnseenCompletion: hasUnseenCompletion,
            isStalled: isStalled
        )
    }
}
