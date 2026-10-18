import Foundation
import AgentDomain
import DesignSystem
import PhloxCore

/// セッション詳細の表示可否を View から切り離した値。
/// 通信状態は `SessionDetailViewModel` が持ち、View はこの値に従って表示する。
public struct SessionDetailPresentationState: Equatable, Sendable {
    public enum Transcript: Equatable, Sendable {
        case unsupported
        case loading
        case empty
        case fetchError
        case messages
    }

    public let displayState: SessionDisplayState?
    public let transcript: Transcript
    public let showsInputBar: Bool
    public let showsStopButton: Bool
    public let showsUsage: Bool
    public let showsStartingBanner: Bool
    public let allowsModelSelection: Bool

    public static func elapsedClock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    public init(
        session: Session,
        status: SessionStatus,
        canInterrupt: Bool,
        hasMessages: Bool,
        isInitialLoading: Bool,
        loadError: String?,
        isRecoveringInitialSend: Bool
    ) {
        guard !session.isPTY else {
            displayState = nil
            transcript = .unsupported
            showsInputBar = false
            showsStopButton = false
            showsUsage = false
            showsStartingBanner = false
            allowsModelSelection = false
            return
        }

        let resolvedState = SessionDisplayState.resolve(
            status,
            hasUnseenCompletion: session.hasUnseenCompletion,
            isStalled: session.isStalled
        )
        displayState = session.agent == .cursor && resolvedState == .approval ? nil : resolvedState
        transcript = if hasMessages {
            .messages
        } else if isInitialLoading {
            .loading
        } else if loadError != nil {
            .fetchError
        } else {
            .empty
        }
        showsStartingBanner = resolvedState == .starting && !isRecoveringInitialSend
        showsInputBar = !showsStartingBanner
        showsStopButton = status == .running && canInterrupt
        showsUsage = showsInputBar
        allowsModelSelection = true
    }
}
