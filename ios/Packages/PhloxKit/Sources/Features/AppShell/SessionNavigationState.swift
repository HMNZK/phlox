import AgentDomain
import DesignSystem
import Foundation
import PhloxCore

public enum AppTab: CaseIterable, Hashable, Sendable {
    case sessions
    case settings
}

/// 下部ナビに必要な対応待ち情報。画面や SwiftUI に依存しない。
public struct SessionNavigationState: Equatable, Sendable {
    public struct AttentionItem: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let displayState: SessionDisplayState
        public let agent: AgentKind
        public let projectName: String?

        public var statusLabel: String {
            displayState.localizedLabel(locale: Locale(identifier: "ja_JP"))
        }

        public var projectLabel: String { projectName ?? "その他" }
    }

    public enum Accessory: Equatable, Sendable {
        case attention
        case offline
    }

    public let attentionItems: [AttentionItem]
    public let badgeCount: Int
    public let accessory: Accessory?

    public var firstAttentionItem: AttentionItem? { attentionItems.first }

    public var sessionsTabAccessibilityLabel: String {
        badgeCount == 0 ? "セッション" : "セッション、対応待ち \(badgeCount) 件"
    }

    private init(attentionItems: [AttentionItem], badgeCount: Int, accessory: Accessory?) {
        self.attentionItems = attentionItems
        self.badgeCount = badgeCount
        self.accessory = accessory
    }

    public static func resolve(
        listState: SessionsState,
        lastKnownSessions: [Session],
        reachability: Reachability
    ) -> SessionNavigationState {
        let badgeSessions: [Session]
        switch reachability {
        case .offlineNetwork, .unreachableHost, .unknown:
            badgeSessions = lastKnownSessions
        case .online:
            switch listState {
            case .loaded(let sessions): badgeSessions = sessions
            case .empty: badgeSessions = []
            case .loading, .offline, .error: badgeSessions = lastKnownSessions
            }
        }
        let badgeCount = makeAttentionItems(from: badgeSessions).count

        let accessory: Accessory
        let attentionItems: [AttentionItem]
        switch reachability {
        case .offlineNetwork, .unreachableHost:
            accessory = .offline
            attentionItems = []
        case .unknown:
            // 判定待ちの締切を超えると、到達性は unknown のまま一覧が offline になる。
            guard case .offline = listState else {
                return SessionNavigationState(attentionItems: [], badgeCount: badgeCount, accessory: nil)
            }
            accessory = .offline
            attentionItems = []
        case .online:
            guard case .loaded(let sessions) = listState, !sessions.isEmpty else {
                return SessionNavigationState(attentionItems: [], badgeCount: badgeCount, accessory: nil)
            }
            attentionItems = makeAttentionItems(from: sessions)
            guard !attentionItems.isEmpty else {
                return SessionNavigationState(attentionItems: [], badgeCount: badgeCount, accessory: nil)
            }
            accessory = .attention
        }
        return SessionNavigationState(
            attentionItems: attentionItems,
            badgeCount: badgeCount,
            accessory: accessory
        )
    }

    private static func makeAttentionItems(from sessions: [Session]) -> [AttentionItem] {
        SessionAttentionQueue.ordered(sessions).map { session in
            return AttentionItem(
                id: session.id,
                name: session.name,
                displayState: session.displayState,
                agent: session.agent,
                projectName: session.projectName
            )
        }
    }
}
