import Foundation
import Observation
import AgentDomain
import DesignSystem
import SessionFeature

public struct TerminalTabID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum ProjectTab: Hashable, Codable, Sendable {
    case chat(SessionID)
    case newChat
    case terminal(TerminalTabID)
    case changes
    case browser
    case simulator
    case file(String)

    var isChat: Bool { if case .chat = self { return true }; return false }
    var persists: Bool {
        switch self {
        case .newChat, .changes, .file: true
        case .chat, .terminal, .browser, .simulator: false
        }
    }

    static func chats(in forest: [SessionTreeNode], candidates: [SessionID]) -> [ProjectTab] {
        let included = Set(candidates)
        func visit(_ nodes: [SessionTreeNode]) -> [ProjectTab] {
            nodes.flatMap { (included.contains($0.id) ? [.chat($0.id)] : []) + visit($0.children) }
        }
        return visit(forest)
    }
}

public struct ProjectTabLayout: Codable, Equatable, Sendable {
    public var items: [ProjectTab] = []
    public var left: ProjectTab?
    public var right: ProjectTab?
    public var focusesRight = false
    public var splitFraction: Double = 0.5
    public init() {}
    public var selected: ProjectTab? { focusesRight ? (right ?? left) : left }
    public func isShown(_ tab: ProjectTab) -> Bool { tab == left || tab == right }
    public func tabs(chats: [ProjectTab]) -> [ProjectTab] { chats + items }

    public mutating func open(_ tab: ProjectTab) {
        if !tab.isChat, !items.contains(tab) { items.append(tab) }
        select(tab)
    }

    public mutating func select(_ tab: ProjectTab) {
        guard tab.isChat || items.contains(tab) else { return }
        if tab == left { focusesRight = false }
        else if tab == right { focusesRight = true }
        else if focusesRight, right != nil { right = tab }
        else { left = tab }
    }

    public mutating func showChat(_ id: SessionID, keeping kept: ProjectTab) {
        if right != nil, !isShown(.chat(id)), isShown(kept) { focusesRight = left == kept }
        select(.chat(id))
    }

    @discardableResult
    public mutating func close(_ tab: ProjectTab, chats: [ProjectTab] = []) -> Bool {
        guard !tab.isChat, let index = items.firstIndex(of: tab) else { return false }
        let ordered = tabs(chats: chats)
        let position = ordered.firstIndex(of: tab) ?? 0
        items.remove(at: index)
        if right == tab { right = nil; focusesRight = false }
        else if left == tab {
            if let right { left = right; self.right = nil }
            else {
                let remaining = tabs(chats: chats)
                left = remaining.isEmpty ? nil : remaining[min(max(0, position - 1), remaining.count - 1)]
            }
            focusesRight = false
        }
        return true
    }

    public mutating func cycle(by offset: Int, chats: [ProjectTab] = []) {
        let ordered = tabs(chats: chats)
        guard !ordered.isEmpty else { return }
        let index = selected.flatMap { ordered.firstIndex(of: $0) } ?? 0
        let count = ordered.count
        select(ordered[((index + offset % count) % count + count) % count])
    }

    public mutating func splitRight(_ tab: ProjectTab, chats: [ProjectTab] = []) {
        let ordered = tabs(chats: chats)
        guard ordered.contains(tab) else { return }
        if left == nil || left == tab {
            guard let other = right.flatMap({ $0 != tab ? $0 : nil }) ?? ordered.first(where: { $0 != tab }) else { return }
            left = other
        }
        right = tab
        focusesRight = true
    }

    public mutating func toggleSplit(chats: [ProjectTab] = []) {
        if right != nil { left = selected; right = nil; focusesRight = false }
        else if let left { splitRight(left, chats: chats) }
    }

    mutating func reconcileChats(previous: [ProjectTab], current: [ProjectTab]) {
        if let right, right.isChat, !current.contains(right) { self.right = nil; focusesRight = false }
        if let left, left.isChat, !current.contains(left) {
            let index = previous.firstIndex(of: left) ?? 0
            let remaining = current + items
            self.left = right ?? (remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)])
            right = nil
            focusesRight = false
        }
    }

    fileprivate var persistenceCopy: Self {
        var copy = self
        copy.items.removeAll { !$0.persists }
        if copy.right?.persists != true { copy.right = nil }
        if copy.left?.persists != true { copy.left = copy.right; copy.right = nil }
        if copy.right == nil { copy.focusesRight = false }
        return copy
    }
}

public struct ProjectTabsSnapshot: Codable, Equatable, Sendable {
    public var projects: [ProjectID: ProjectTabLayout] = [:]
    public init() {}
    public mutating func forgetProject(_ id: ProjectID) { projects[id] = nil }
}

public struct HiddenAttentionSummary: Equatable, Sendable {
    public let kind: AttentionKind?
    public let count: Int
    public static func make(hiddenStates: [SessionDisplayState]) -> Self? {
        let kinds = hiddenStates.compactMap(\.attentionKind)
        guard let first = kinds.first else { return nil }
        return Self(kind: kinds.allSatisfy { $0 == first } ? first : nil, count: kinds.count)
    }
}

public enum CloseCommandTarget: Equatable, Sendable {
    case tab(ProjectTab)
    case session(SessionID)
    case project(ProjectID)
    case gridTile(SessionID)
}

@MainActor @Observable
public final class ProjectTabStore {
    public private(set) var snapshot: ProjectTabsSnapshot
    @ObservationIgnored private let defaults: UserDefaults?
    static let defaultsKey = "phlox.projectTabs.v1"
    static let legacyDefaultsKey = "phlox.sessionTabs.v1"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(ProjectTabsSnapshot.self, from: data) { snapshot = decoded }
        else { snapshot = ProjectTabsSnapshot() }
    }

    public func layout(for id: ProjectID) -> ProjectTabLayout { snapshot.projects[id] ?? ProjectTabLayout() }
    public func updateLayout(for id: ProjectID, _ change: (inout ProjectTabLayout) -> Void) {
        var layout = layout(for: id)
        change(&layout)
        guard snapshot.projects[id] != layout else { return }
        snapshot.projects[id] = layout
        persist()
    }
    public func forgetProject(_ id: ProjectID) { snapshot.forgetProject(id); persist() }

    public func closeTarget(projectID: ProjectID?, selectedSession: SessionID?, viewMode: ViewMode) -> CloseCommandTarget? {
        if viewMode == .grid { return selectedSession.map(CloseCommandTarget.gridTile) }
        if let projectID, let selected = layout(for: projectID).selected {
            if case .chat(let id) = selected { return .session(id) }
            return .tab(selected)
        }
        return selectedSession.map(CloseCommandTarget.session)
    }

    public func migrateLegacy(sessionProjects: [SessionID: ProjectID], projects: [Project]) {
        guard let defaults, defaults.object(forKey: Self.defaultsKey) == nil else { return }
        if let data = defaults.data(forKey: Self.legacyDefaultsKey),
           let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            for sessionID in legacy.sessions.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
                guard let projectID = sessionProjects[sessionID],
                      let project = projects.first(where: { $0.id == projectID }),
                      let old = legacy.sessions[sessionID] else { continue }
                var layout = layout(for: projectID)
                for tab in old.tabs {
                    switch tab {
                    case .changes: layout.open(.changes)
                    case .file(let path):
                        let root = URL(fileURLWithPath: project.directoryPath).standardizedFileURL.resolvingSymlinksInPath()
                        let file = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
                        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                        var isDirectory: ObjCBool = false
                        guard !path.hasPrefix("/"), file.path.hasPrefix(prefix),
                              FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                        layout.open(.file(path))
                    default: break
                    }
                }
                if !layout.items.isEmpty { snapshot.projects[projectID] = layout }
            }
        }
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        var saved = snapshot
        saved.projects = saved.projects.mapValues(\.persistenceCopy)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    private enum LegacyTab: Codable { case conversation, terminal, changes, browser, simulator, file(String) }
    private struct LegacyLayout: Codable { var tabs: [LegacyTab] }
    private struct LegacySnapshot: Codable { var sessions: [SessionID: LegacyLayout] }
}

extension DashboardViewModel {
    public func chatTabs(in projectID: ProjectID) -> [ProjectTab] {
        ProjectTab.chats(in: sessionForest(in: projectID), candidates: tabSessionNodes(in: projectID).map(\.id))
    }

    public func numberedTabs(router: AppRouter) -> [ProjectTab] {
        if router.viewMode == .grid { return gridTileOrder().map(ProjectTab.chat) }
        guard let id = router.selectedProjectID ?? router.selectedSession.flatMap({ sessionNode(id: $0)?.projectID }) else { return [] }
        return router.tabs.layout(for: id).tabs(chats: chatTabs(in: id))
    }
}
