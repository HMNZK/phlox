import Foundation
import Observation
import AgentDomain

@Observable
public final class SessionTreeViewModel {
    public private(set) var expandedSessionIDs: Set<SessionID>

    public init(expandedSessionIDs: Set<SessionID> = []) {
        self.expandedSessionIDs = expandedSessionIDs
    }

    public func rows(from forest: [SessionTreeNode]) -> [Row] {
        forest.flatMap(visibleRows)
    }

    public func toggleExpansion(for id: SessionID, in forest: [SessionTreeNode]) {
        guard let node = findNode(id, in: forest), !node.children.isEmpty else { return }
        if expandedSessionIDs.contains(id) {
            expandedSessionIDs.remove(id)
        } else {
            expandedSessionIDs.insert(id)
        }
    }

    public func isExpanded(_ id: SessionID) -> Bool {
        expandedSessionIDs.contains(id)
    }

    private func visibleRows(from node: SessionTreeNode) -> [Row] {
        let isExpanded = expandedSessionIDs.contains(node.id)
        let row = Row(node: node, isExpanded: isExpanded)
        guard isExpanded else { return [row] }
        return [row] + node.children.flatMap(visibleRows)
    }

    private func findNode(_ id: SessionID, in nodes: [SessionTreeNode]) -> SessionTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id, in: node.children) {
                return found
            }
        }
        return nil
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: SessionID
        public let parentSessionID: SessionID?
        public let projectID: ProjectID?
        public let launchContext: SessionLaunchContext
        public let status: SessionStatus
        public let name: String
        public let agentRef: AgentRef
        public let depth: Int
        public let hasChildren: Bool
        public let isExpanded: Bool

        public var agentKind: AgentKind? { agentRef.builtinKind }

        public var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "#" + String(id.rawValue.uuidString.prefix(6)) : trimmed
        }

        public init(node: SessionTreeNode, isExpanded: Bool) {
            self.id = node.id
            self.parentSessionID = node.parentSessionID
            self.projectID = node.projectID
            self.launchContext = node.launchContext
            self.status = node.status
            self.name = node.name
            self.agentRef = node.agentRef
            self.depth = node.depth
            self.hasChildren = !node.children.isEmpty
            self.isExpanded = isExpanded
        }
    }
}
