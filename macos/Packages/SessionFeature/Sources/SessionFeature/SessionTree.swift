import Foundation
import AgentDomain

public struct SessionTreeInput: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let parentSessionID: SessionID?
    public let projectID: ProjectID?
    public let launchContext: SessionLaunchContext
    public let status: SessionStatus
    public let name: String
    public let agentRef: AgentRef

    public var agentKind: AgentKind? { agentRef.builtinKind }

    public init(
        id: SessionID,
        parentSessionID: SessionID?,
        projectID: ProjectID?,
        launchContext: SessionLaunchContext,
        status: SessionStatus,
        name: String,
        agentRef: AgentRef
    ) {
        self.id = id
        self.parentSessionID = parentSessionID
        self.projectID = projectID
        self.launchContext = launchContext
        self.status = status
        self.name = name
        self.agentRef = agentRef
    }
}

public struct SessionTreeNode: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let parentSessionID: SessionID?
    public let projectID: ProjectID?
    public let launchContext: SessionLaunchContext
    public let status: SessionStatus
    public let name: String
    public let agentRef: AgentRef
    public let children: [SessionTreeNode]
    public let depth: Int

    public var agentKind: AgentKind? { agentRef.builtinKind }

    public init(
        input: SessionTreeInput,
        children: [SessionTreeNode],
        depth: Int
    ) {
        self.id = input.id
        self.parentSessionID = input.parentSessionID
        self.projectID = input.projectID
        self.launchContext = input.launchContext
        self.status = input.status
        self.name = input.name
        self.agentRef = input.agentRef
        self.children = children
        self.depth = depth
    }
}

public enum SessionTree {
    public static func buildForest(from inputs: [SessionTreeInput]) -> [SessionTreeNode] {
        let orderedInputs = uniqueInputsPreservingOrder(inputs)
        let inputsByID = Dictionary(uniqueKeysWithValues: orderedInputs.map { ($0.id, $0) })
        var childrenByParent: [SessionID: [SessionTreeInput]] = [:]
        for input in orderedInputs {
            guard let parentSessionID = input.parentSessionID,
                  inputsByID[parentSessionID] != nil else {
                continue
            }
            childrenByParent[parentSessionID, default: []].append(input)
        }

        var emittedIDs = Set<SessionID>()
        var forest: [SessionTreeNode] = []

        for input in orderedInputs where isRoot(input, in: inputsByID) {
            if let node = buildNode(
                input,
                depth: 0,
                childrenByParent: childrenByParent,
                activePath: [],
                emittedIDs: &emittedIDs
            ) {
                forest.append(node)
            }
        }

        for input in orderedInputs where !emittedIDs.contains(input.id) {
            if let node = buildNode(
                input,
                depth: 0,
                childrenByParent: childrenByParent,
                activePath: [],
                emittedIDs: &emittedIDs
            ) {
                forest.append(node)
            }
        }

        return forest
    }

    private static func uniqueInputsPreservingOrder(_ inputs: [SessionTreeInput]) -> [SessionTreeInput] {
        var seenIDs = Set<SessionID>()
        var uniqueInputs: [SessionTreeInput] = []
        uniqueInputs.reserveCapacity(inputs.count)

        for input in inputs where seenIDs.insert(input.id).inserted {
            uniqueInputs.append(input)
        }

        return uniqueInputs
    }

    private static func isRoot(
        _ input: SessionTreeInput,
        in inputsByID: [SessionID: SessionTreeInput]
    ) -> Bool {
        guard let parentSessionID = input.parentSessionID else { return true }
        return inputsByID[parentSessionID] == nil
    }

    private static func buildNode(
        _ input: SessionTreeInput,
        depth: Int,
        childrenByParent: [SessionID: [SessionTreeInput]],
        activePath: Set<SessionID>,
        emittedIDs: inout Set<SessionID>
    ) -> SessionTreeNode? {
        guard !activePath.contains(input.id),
              emittedIDs.insert(input.id).inserted else {
            return nil
        }

        var nextActivePath = activePath
        nextActivePath.insert(input.id)

        let children = (childrenByParent[input.id] ?? []).compactMap { child in
            buildNode(
                child,
                depth: depth + 1,
                childrenByParent: childrenByParent,
                activePath: nextActivePath,
                emittedIDs: &emittedIDs
            )
        }

        return SessionTreeNode(input: input, children: children, depth: depth)
    }
}
