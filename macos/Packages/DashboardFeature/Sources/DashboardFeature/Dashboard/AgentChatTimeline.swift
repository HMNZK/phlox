import Foundation
import AgentDomain
import SessionFeature

/// エージェントビューのタイムライン構築に渡すセッション入力。
/// `TeamTimelineSource` に親子情報（parentSessionID）を加えたもの。
public struct AgentTimelineSource: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let parentSessionID: SessionID?
    public let displayName: String
    public let agentDescriptor: AgentDescriptor
    public let messages: [TeamTimelineSourceMessage]

    public init(
        id: SessionID,
        parentSessionID: SessionID?,
        displayName: String,
        agentDescriptor: AgentDescriptor,
        messages: [TeamTimelineSourceMessage]
    ) {
        self.id = id
        self.parentSessionID = parentSessionID
        self.displayName = displayName
        self.agentDescriptor = agentDescriptor
        self.messages = messages
    }
}

/// タイムラインの1エントリ。メッセージ、または spawn 位置に埋め込まれたサブセッション（再帰）。
public enum AgentTimelineEntry: Identifiable, Equatable, Sendable {
    case message(TeamTimelineItem)
    case subsession(AgentTimelineSubtree)

    public var id: String {
        switch self {
        case .message(let item): item.id
        case .subsession(let subtree): "subsession-\(subtree.sessionID.rawValue.uuidString)"
        }
    }
}

/// 埋め込まれたサブセッション（子孫を再帰的に含む）。
public struct AgentTimelineSubtree: Identifiable, Equatable, Sendable {
    public let sessionID: SessionID
    public let displayName: String
    public let agentDescriptor: AgentDescriptor
    public let entries: [AgentTimelineEntry]

    public var id: SessionID { sessionID }

    public init(
        sessionID: SessionID,
        displayName: String,
        agentDescriptor: AgentDescriptor,
        entries: [AgentTimelineEntry]
    ) {
        self.sessionID = sessionID
        self.displayName = displayName
        self.agentDescriptor = agentDescriptor
        self.entries = entries
    }
}

enum AgentSubsessionTapRegion: Equatable, Sendable {
    case header
    case cardChrome
    case messageBody
}

enum AgentSubsessionTapPolicy {
    static func opensSingleView(for region: AgentSubsessionTapRegion) -> Bool {
        switch region {
        case .header, .cardChrome:
            true
        case .messageBody:
            false
        }
    }
}

enum AgentTimelineCollapsePolicy {
    static func visibleEntryIDs(
        entries: [AgentTimelineEntry],
        collapsedSessionIDs: Set<SessionID>
    ) -> [String] {
        var ids: [String] = []
        appendVisibleEntryIDs(
            entries: entries,
            collapsedSessionIDs: collapsedSessionIDs,
            to: &ids
        )
        return ids
    }

    private static func appendVisibleEntryIDs(
        entries: [AgentTimelineEntry],
        collapsedSessionIDs: Set<SessionID>,
        to ids: inout [String]
    ) {
        for entry in entries {
            ids.append(entry.id)
            guard case .subsession(let subtree) = entry,
                  !collapsedSessionIDs.contains(subtree.sessionID) else {
                continue
            }
            appendVisibleEntryIDs(
                entries: subtree.entries,
                collapsedSessionIDs: collapsedSessionIDs,
                to: &ids
            )
        }
    }
}

/// エージェントビューのタイムライン木を構築する純ロジック（R6）。
///
/// 契約（tasks/task-2.md 参照）:
/// - `rootID` のセッションを幹とし、その子セッションを「spawn 位置」へ埋め込む。
/// - 子の anchor＝（間引き前の）子自身の messages を transcript 順に走査して最初の非 nil timestamp。
///   子自身に timestamp が無ければ、子セッションを sources 出現順に再帰走査して最初に見つかった anchor。
///   anchor が nil なら親エントリ列の末尾。
/// - 子は「timestamp <= anchor の最後の親メッセージ」の直後に挿入する。同位置の兄弟は anchor 昇順、
///   同 anchor は sources の出現順。
/// - 孫以降も同じ規則で再帰的に埋め込む。
/// - `messageLimitPerSession` > 0 のとき、各セッションのメッセージを「直近 N 件」に間引く（表示上限。
///   anchor の算出は間引き前の値を使う）。0 以下は無制限。
/// - rootID が sources に無ければ []。親が sources に無い孤児は無視する。
public enum AgentChatTimelineBuilder {
    public static func build(
        sources: [AgentTimelineSource],
        rootID: SessionID,
        messageLimitPerSession: Int
    ) -> [AgentTimelineEntry] {
        let context = BuildContext(sources: sources, messageLimitPerSession: messageLimitPerSession)
        guard context.sourceByID[rootID] != nil else {
            return []
        }
        return context.entries(for: rootID)
    }

    private struct BuildContext {
        let sourceByID: [SessionID: AgentTimelineSource]
        let sourceOrderByID: [SessionID: Int]
        let childrenByParentID: [SessionID: [SessionID]]
        let anchorByID: [SessionID: Date?]
        let messageLimitPerSession: Int

        init(sources: [AgentTimelineSource], messageLimitPerSession: Int) {
            var sourceByID: [SessionID: AgentTimelineSource] = [:]
            var sourceOrderByID: [SessionID: Int] = [:]
            var orderedSourceIDs: [SessionID] = []

            for (index, source) in sources.enumerated() where sourceByID[source.id] == nil {
                sourceByID[source.id] = source
                sourceOrderByID[source.id] = index
                orderedSourceIDs.append(source.id)
            }

            var childrenByParentID: [SessionID: [SessionID]] = [:]
            for sourceID in orderedSourceIDs {
                guard let parentID = sourceByID[sourceID]?.parentSessionID else {
                    continue
                }
                childrenByParentID[parentID, default: []].append(sourceID)
            }

            self.sourceByID = sourceByID
            self.sourceOrderByID = sourceOrderByID
            self.childrenByParentID = childrenByParentID
            self.anchorByID = Self.computeAnchors(
                sourceByID: sourceByID,
                childrenByParentID: childrenByParentID,
                orderedSourceIDs: orderedSourceIDs
            )
            self.messageLimitPerSession = messageLimitPerSession
        }

        func entries(for rootID: SessionID) -> [AgentTimelineEntry] {
            guard sourceByID[rootID] != nil else {
                return []
            }

            var entriesByID: [SessionID: [AgentTimelineEntry]] = [:]
            var activePath: Set<SessionID> = []
            var stack: [BuildFrame] = []

            func push(_ sessionID: SessionID) {
                guard sourceByID[sessionID] != nil, !activePath.contains(sessionID) else {
                    return
                }
                activePath.insert(sessionID)
                let childIDs = childrenByParentID[sessionID, default: []]
                    .filter { sourceByID[$0] != nil && !activePath.contains($0) }
                stack.append(BuildFrame(sessionID: sessionID, childIDs: childIDs))
            }

            push(rootID)

            while !stack.isEmpty {
                let frameIndex = stack.count - 1
                if stack[frameIndex].nextChildIndex < stack[frameIndex].childIDs.count {
                    let childID = stack[frameIndex].childIDs[stack[frameIndex].nextChildIndex]
                    stack[frameIndex].nextChildIndex += 1
                    push(childID)
                    continue
                }

                let frame = stack.removeLast()
                entriesByID[frame.sessionID] = entries(
                    for: frame.sessionID,
                    childIDs: frame.childIDs,
                    childEntriesByID: entriesByID
                )
                activePath.remove(frame.sessionID)
            }

            return entriesByID[rootID] ?? []
        }

        private func entries(
            for sessionID: SessionID,
            childIDs: [SessionID],
            childEntriesByID: [SessionID: [AgentTimelineEntry]]
        ) -> [AgentTimelineEntry] {
            guard let source = sourceByID[sessionID] else {
                return []
            }

            let visibleMessages = limitedMessages(source.messages)
            let messageEntries = visibleMessages.map { message in
                AgentTimelineEntry.message(item(for: message, in: source))
            }

            let childPlacements = childIDs.map { childID in
                let childAnchor = precomputedAnchor(for: childID)
                return ChildPlacement(
                    sessionID: childID,
                    anchor: childAnchor,
                    insertionSlot: insertionSlot(
                        for: childAnchor,
                        in: visibleMessages
                    ),
                    sourceOrder: sourceOrderByID[childID] ?? Int.max
                )
            }

            let placementsBySlot = Dictionary(grouping: childPlacements, by: \.insertionSlot)
                .mapValues { placements in
                    placements.sorted(by: childPlacementPrecedes)
                }

            var entries: [AgentTimelineEntry] = []
            entries.reserveCapacity(messageEntries.count + childPlacements.count)

            for index in messageEntries.indices {
                appendSubtrees(
                    for: placementsBySlot[index] ?? [],
                    childEntriesByID: childEntriesByID,
                    to: &entries
                )
                entries.append(messageEntries[index])
            }
            appendSubtrees(
                for: placementsBySlot[messageEntries.count] ?? [],
                childEntriesByID: childEntriesByID,
                to: &entries
            )

            return entries
        }

        private static func computeAnchors(
            sourceByID: [SessionID: AgentTimelineSource],
            childrenByParentID: [SessionID: [SessionID]],
            orderedSourceIDs: [SessionID]
        ) -> [SessionID: Date?] {
            var anchorByID: [SessionID: Date?] = [:]

            for sourceID in orderedSourceIDs {
                computeAnchor(
                    for: sourceID,
                    sourceByID: sourceByID,
                    childrenByParentID: childrenByParentID,
                    anchorByID: &anchorByID
                )
            }

            return anchorByID
        }

        private static func computeAnchor(
            for rootID: SessionID,
            sourceByID: [SessionID: AgentTimelineSource],
            childrenByParentID: [SessionID: [SessionID]],
            anchorByID: inout [SessionID: Date?]
        ) {
            guard sourceByID[rootID] != nil, !anchorByID.keys.contains(rootID) else {
                return
            }

            var activePath: Set<SessionID> = []
            var stack: [AnchorFrame] = [AnchorFrame(sessionID: rootID, expanded: false)]

            while let frame = stack.popLast() {
                guard sourceByID[frame.sessionID] != nil else {
                    continue
                }
                if anchorByID.keys.contains(frame.sessionID) {
                    continue
                }

                if frame.expanded {
                    anchorByID[frame.sessionID] = firstAnchor(
                        for: frame.sessionID,
                        sourceByID: sourceByID,
                        childrenByParentID: childrenByParentID,
                        anchorByID: anchorByID
                    )
                    activePath.remove(frame.sessionID)
                    continue
                }

                guard !activePath.contains(frame.sessionID) else {
                    continue
                }

                activePath.insert(frame.sessionID)
                stack.append(AnchorFrame(sessionID: frame.sessionID, expanded: true))

                let source = sourceByID[frame.sessionID]
                if source?.messages.lazy.compactMap(\.timestamp).first == nil {
                    for childID in childrenByParentID[frame.sessionID, default: []].reversed()
                    where sourceByID[childID] != nil
                        && !activePath.contains(childID)
                        && !anchorByID.keys.contains(childID) {
                        stack.append(AnchorFrame(sessionID: childID, expanded: false))
                    }
                }
            }
        }

        private static func firstAnchor(
            for sessionID: SessionID,
            sourceByID: [SessionID: AgentTimelineSource],
            childrenByParentID: [SessionID: [SessionID]],
            anchorByID: [SessionID: Date?]
        ) -> Date? {
            guard let source = sourceByID[sessionID] else {
                return nil
            }
            if let ownAnchor = source.messages.lazy.compactMap(\.timestamp).first {
                return ownAnchor
            }
            for childID in childrenByParentID[sessionID, default: []] {
                if anchorByID.keys.contains(childID), let childAnchor = anchorByID[childID] ?? nil {
                    return childAnchor
                }
            }
            return nil
        }

        private func appendSubtrees(
            for placements: [ChildPlacement],
            childEntriesByID: [SessionID: [AgentTimelineEntry]],
            to output: inout [AgentTimelineEntry]
        ) {
            for placement in placements {
                guard let source = sourceByID[placement.sessionID] else {
                    continue
                }
                output.append(
                    .subsession(
                        AgentTimelineSubtree(
                            sessionID: source.id,
                            displayName: source.displayName,
                            agentDescriptor: source.agentDescriptor,
                            entries: childEntriesByID[source.id] ?? []
                        )
                    )
                )
            }
        }

        private func precomputedAnchor(for sessionID: SessionID) -> Date? {
            guard anchorByID.keys.contains(sessionID) else {
                return nil
            }
            return anchorByID[sessionID] ?? nil
        }

        private func limitedMessages(_ messages: [TeamTimelineSourceMessage]) -> [TeamTimelineSourceMessage] {
            guard messageLimitPerSession > 0, messages.count > messageLimitPerSession else {
                return messages
            }
            return Array(messages.suffix(messageLimitPerSession))
        }

        private func item(
            for message: TeamTimelineSourceMessage,
            in source: AgentTimelineSource
        ) -> TeamTimelineItem {
            TeamTimelineItem(
                id: "\(source.id.rawValue.uuidString):\(message.id)",
                sessionID: source.id,
                sessionDisplayName: source.displayName,
                agentDescriptor: source.agentDescriptor,
                sourceMessageID: message.id,
                timestamp: message.timestamp,
                content: message.content
            )
        }

        private func insertionSlot(
            for anchor: Date?,
            in messages: [TeamTimelineSourceMessage]
        ) -> Int {
            guard let anchor else {
                return messages.count
            }

            var slot = 0
            for (index, message) in messages.enumerated() {
                guard let timestamp = message.timestamp, timestamp <= anchor else {
                    continue
                }
                slot = index + 1
            }
            return slot
        }

        private func childPlacementPrecedes(_ lhs: ChildPlacement, _ rhs: ChildPlacement) -> Bool {
            switch (lhs.anchor, rhs.anchor) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.sourceOrder < rhs.sourceOrder
            }
        }
    }

    private struct ChildPlacement {
        let sessionID: SessionID
        let anchor: Date?
        let insertionSlot: Int
        let sourceOrder: Int
    }

    private struct BuildFrame {
        let sessionID: SessionID
        let childIDs: [SessionID]
        var nextChildIndex = 0
    }

    private struct AnchorFrame {
        let sessionID: SessionID
        let expanded: Bool
    }
}
