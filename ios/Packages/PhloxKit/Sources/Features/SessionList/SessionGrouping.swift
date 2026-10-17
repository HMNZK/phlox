import DesignSystem
import DesignSystemIOS
import Foundation
import PhloxCore

/// Mac の AttentionQueue と同じ待ち時間順。同時刻・時刻なし同士は受信順を保つ。
enum SessionAttentionQueue {
    static func ordered(_ sessions: [Session]) -> [Session] {
        sessions.enumerated()
            .filter { $0.element.displayState.attentionKind != nil }
            .sorted { lhs, rhs in
                switch (lhs.element.statusEnteredAt, rhs.element.statusEnteredAt) {
                case let (l?, r?) where l != r: l < r
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

/// セッション一覧に表示する木の 1 行。
public struct SessionListTreeNode: Identifiable, Equatable, Sendable {
    public let session: Session
    public let children: [SessionListTreeNode]

    public var id: String { session.id }
    public var descendantCount: Int {
        children.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    fileprivate var sessions: [Session] {
        [session] + children.flatMap(\.sessions)
    }

    public func collapsedChildCountLabel(isExpanded: Bool) -> String? {
        guard !children.isEmpty, !isExpanded else { return nil }
        return "+\(descendantCount)"
    }

    public init(session: Session, children: [SessionListTreeNode]) {
        self.session = session
        self.children = children
    }
}

/// 折りたたんだプロジェクト欄に表示する状態ごとの件数。
public struct SessionListCountEntry: Equatable, Sendable, Identifiable {
    public let state: SessionDisplayState
    public let count: Int

    public var id: String {
        state == .doneUnread ? "未読" : state.localizedLabel(locale: Locale(identifier: "ja_JP"))
    }
    public var label: String { "\(id) \(count)" }

    public init(state: SessionDisplayState, count: Int) {
        self.state = state
        self.count = count
    }
}

public struct SessionListCollapsedSummary: Equatable, Sendable {
    public let entries: [SessionListCountEntry]

    public var label: String { entries.map(\.label).joined(separator: " ") }

    public init(sessions: [Session]) {
        let order: [SessionDisplayState] = [
            .approval, .question, .error, .stalled, .running, .doneUnread,
        ]
        entries = order.compactMap { state in
            let count = sessions.lazy.filter { $0.displayState == state }.count
            return count == 0 ? nil : SessionListCountEntry(state: state, count: count)
        }
    }
}

/// 1 つのプロジェクト（または「その他」）に属する一覧欄。
public struct ProjectGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let projectID: String?
    public let title: String
    public let isOther: Bool
    /// 欄の VoiceOver 件数用。対応待ち欄に出る行も含む。
    public let allSessions: [Session]
    /// 一覧に表示する木。対応待ちの行は含まない。
    public let roots: [SessionListTreeNode]
    public let collapsedSummary: SessionListCollapsedSummary

    public var sessionCount: Int { allSessions.count }
    public var addSessionDraft: SessionComposeDraft {
        SessionComposeDraft(project: title, projectID: projectID)
    }

    public init(
        id: String,
        projectID: String?,
        title: String,
        isOther: Bool = false,
        allSessions: [Session],
        roots: [SessionListTreeNode]
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.isOther = isOther
        self.allSessions = allSessions
        self.roots = roots
        self.collapsedSummary = SessionListCollapsedSummary(sessions: roots.flatMap(\.sessions))
    }
}

/// 一覧の各欄を作る View 非依存の投影。
public struct SessionListProjection: Equatable, Sendable {
    public let attentionSessions: [Session]
    public let projectGroups: [ProjectGroup]
    public let otherGroup: ProjectGroup?

    public static func make(sessions: [Session], projects: [ProjectSummary]? = nil) -> SessionListProjection {
        let attentionSessions = SessionAttentionQueue.ordered(sessions)
        let projectOrder = projects ?? []
        var projectsByName: [String: ProjectSummary] = [:]
        var projectsByID: [String: ProjectSummary] = [:]
        for project in projectOrder {
            if projectsByName[project.name] == nil { projectsByName[project.name] = project }
            if projectsByID[project.id] == nil { projectsByID[project.id] = project }
        }

        var projectSessions: [String: [Session]] = [:]
        var projectKeyOrder: [String] = []
        var otherSessions: [Session] = []

        for session in sessions {
            guard let key = projectKey(for: session, projectsByName: projectsByName) else {
                otherSessions.append(session)
                continue
            }
            if projectSessions[key] == nil { projectKeyOrder.append(key) }
            projectSessions[key, default: []].append(session)
        }

        var orderedProjectKeys: [String] = []
        for project in projectOrder {
            let key = "id:\(project.id)"
            if projectSessions[key] != nil, !orderedProjectKeys.contains(key) {
                orderedProjectKeys.append(key)
            }
        }
        for key in projectKeyOrder where !orderedProjectKeys.contains(key) {
            orderedProjectKeys.append(key)
        }

        let projectGroups = orderedProjectKeys.compactMap { key -> ProjectGroup? in
            guard let allSessions = projectSessions[key] else { return nil }
            let roots = makeForest(from: allSessions.filter { $0.displayState.attentionKind == nil })
            guard !roots.isEmpty else { return nil }
            let projectID = key.hasPrefix("id:") ? String(key.dropFirst(3)) : nil
            let title = projectID.flatMap { projectsByID[$0]?.name }
                ?? allSessions.first(where: { $0.projectName != nil })?.projectName
                ?? projectID
                ?? key
            return ProjectGroup(
                id: key,
                projectID: projectID,
                title: title,
                allSessions: allSessions,
                roots: roots
            )
        }

        let otherRoots = makeForest(from: otherSessions.filter { $0.displayState.attentionKind == nil })
        let otherGroup = otherRoots.isEmpty ? nil : ProjectGroup(
            id: "__other__",
            projectID: nil,
            title: "その他",
            isOther: true,
            allSessions: otherSessions,
            roots: otherRoots
        )

        return SessionListProjection(
            attentionSessions: attentionSessions,
            projectGroups: projectGroups,
            otherGroup: otherGroup
        )
    }

    private init(
        attentionSessions: [Session],
        projectGroups: [ProjectGroup],
        otherGroup: ProjectGroup?
    ) {
        self.attentionSessions = attentionSessions
        self.projectGroups = projectGroups
        self.otherGroup = otherGroup
    }

    private static func projectKey(
        for session: Session,
        projectsByName: [String: ProjectSummary]
    ) -> String? {
        if let projectID = session.projectId { return "id:\(projectID)" }
        if let projectName = session.projectName {
            return projectsByName[projectName].map { "id:\($0.id)" } ?? "name:\(projectName)"
        }
        return nil
    }

    private static func makeForest(from sessions: [Session]) -> [SessionListTreeNode] {
        var orderedSessions: [Session] = []
        var sessionsByID: [String: Session] = [:]
        for session in sessions where sessionsByID[session.id] == nil {
            sessionsByID[session.id] = session
            orderedSessions.append(session)
        }

        var childrenByParent: [String: [Session]] = [:]
        for session in orderedSessions {
            guard let parentID = session.parentSessionId,
                  parentID != session.id,
                  sessionsByID[parentID] != nil else {
                continue
            }
            childrenByParent[parentID, default: []].append(session)
        }

        var emitted = Set<String>()
        var roots: [SessionListTreeNode] = []
        let rootSessions = orderedSessions.filter { session in
            guard let parentID = session.parentSessionId,
                  sessionsByID[parentID] != nil else {
                return true
            }
            return parentID == session.id
        }
        for session in rootSessions {
            if let node = makeNode(session, childrenByParent: childrenByParent, path: [], emitted: &emitted) {
                roots.append(node)
            }
        }
        for session in orderedSessions where !emitted.contains(session.id) {
            if let node = makeNode(session, childrenByParent: childrenByParent, path: [], emitted: &emitted) {
                roots.append(node)
            }
        }
        return roots
    }

    private static func makeNode(
        _ session: Session,
        childrenByParent: [String: [Session]],
        path: Set<String>,
        emitted: inout Set<String>
    ) -> SessionListTreeNode? {
        guard !path.contains(session.id), emitted.insert(session.id).inserted else { return nil }
        var nextPath = path
        nextPath.insert(session.id)
        let children = (childrenByParent[session.id] ?? []).compactMap { child in
            makeNode(child, childrenByParent: childrenByParent, path: nextPath, emitted: &emitted)
        }
        return SessionListTreeNode(session: session, children: children)
    }

}

public enum SessionListNameTone: Equatable, Sendable {
    case secondary
    case primary
}

/// 行の状態語、名前の強調、VoiceOver 文言を決める純粋な表示モデル。
public struct SessionListRowPresentation: Equatable, Sendable {
    public let name: String
    public let state: SessionDisplayState
    public let depth: Int

    public var nameTone: SessionListNameTone { isUnread ? .primary : .secondary }
    public var isSemibold: Bool { isUnread }
    public var isUnread: Bool { state == .doneUnread }
    public var statusLabel: String? {
        state == .idle ? nil : state.localizedLabel(locale: Locale(identifier: "ja_JP"))
    }
    public var accessibilityLabel: String {
        var parts = [name]
        if let statusLabel { parts.append(statusLabel) }
        if isUnread { parts.append("未読") }
        if depth > 0 { parts.append("\(depth) 段下の子セッション") }
        return parts.joined(separator: "、")
    }

    public init(session: Session, depth: Int) {
        name = session.name
        state = session.displayState
        self.depth = depth
    }
}

public enum SessionListAccessibility {
    public static func projectHeader(name: String, count: Int, isExpanded: Bool) -> String {
        "\(name)、\(count) 件、\(isExpanded ? "展開中" : "折りたたみ中")"
    }

    public static func childDisclosure(name: String, count: Int, isExpanded: Bool) -> String {
        "\(name) の子セッション \(count) 件、\(isExpanded ? "展開中" : "折りたたみ中")"
    }

    public static func addSession(projectName: String) -> String {
        "\(projectName) で新規チャット"
    }
}
