import Foundation

struct GitHistoryCommit: Identifiable, Equatable, Sendable {
    let id: String
    let parents: [String]
    let summary: String
    let author: String
    let date: Date
    var refs: [String] = []
    var shortID: String { String(id.prefix(7)) }
}

struct GitBranch: Identifiable, Equatable, Sendable {
    let name: String
    let current: Bool
    var tracked = false
    var id: String { name }
    var remote: String { String(name.split(separator: "/", maxSplits: 1).first ?? "") }
    var localName: String { String(name.split(separator: "/", maxSplits: 1).last ?? "") }
}

struct GitStash: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let message: String
    let date: Date
    var source: WorkingTreeSource { .stash(id: id, name: name) }
}

enum GitHistorySection: String, CaseIterable, Hashable, Sendable {
    case commits, branches, remotes, stashes, graph
    var title: String {
        switch self {
        case .commits: "コミット"
        case .branches: "ブランチ"
        case .remotes: "リモートブランチ"
        case .stashes: "スタッシュ"
        case .graph: "グラフ"
        }
    }
    var storageKey: String { "phlox.inspector.git.\(rawValue)Expanded" }
}

/// 上半分は前行の親レーン、下半分は次行の親レーンに接続する。
struct GitGraphRow: Equatable, Sendable {
    struct Edge: Equatable, Sendable {
        let from: Int
        let to: Int
        let color: Int
    }
    let commit: GitHistoryCommit
    let lane: Int
    let currentLane: Int?
    let width: Int
    let incoming: [Edge]
    let outgoing: [Edge]

    static func make(_ commits: [GitHistoryCommit]) -> [Self] {
        var lanes: [String] = []
        var currentIDs = Set(commits.filter { $0.refs.contains { $0 == "HEAD" || $0.hasPrefix("HEAD -> ") } }.map(\.id))
        for commit in commits where currentIDs.contains(commit.id) { currentIDs.formUnion(commit.parents) }
        let rows: [Self] = commits.map { commit in
            let before = lanes
            let lane: Int
            if let existing = lanes.firstIndex(of: commit.id) { lane = existing }
            else { lane = lanes.count; lanes.append(commit.id) }
            let top = lanes
            lanes.remove(at: lane)
            for (offset, parent) in commit.parents.enumerated() where !lanes.contains(parent) {
                lanes.insert(parent, at: min(lane + offset, lanes.count))
            }
            var incoming: [Edge] = []
            var outgoing: [Edge] = []
            for (index, id) in top.enumerated() {
                if id == commit.id {
                    if before.contains(id) { incoming.append(.init(from: index, to: lane, color: index)) }
                    for parent in commit.parents {
                        if let target = lanes.firstIndex(of: parent) {
                            outgoing.append(.init(from: lane, to: target, color: target))
                        }
                    }
                } else if let target = lanes.firstIndex(of: id) {
                    incoming.append(.init(from: index, to: index, color: index))
                    outgoing.append(.init(from: index, to: target, color: target))
                }
            }
            return .init(commit: commit, lane: lane, currentLane: top.firstIndex(where: { currentIDs.contains($0) }),
                         width: max(top.count, lanes.count), incoming: incoming, outgoing: outgoing)
        }
        let width = rows.map(\.width).max() ?? 0
        return rows.map { .init(commit: $0.commit, lane: $0.lane, currentLane: $0.currentLane, width: width, incoming: $0.incoming, outgoing: $0.outgoing) }
    }
}

enum GitHistoryRowID: Hashable {
    case change(GitChangeSelection)
    case commit(String, graph: Bool)
    case branch(String)
    case remote(String)
    case stash(String)
    case file(GitChangeSelection, graph: Bool)
}

struct GitGraphBadge: Identifiable, Equatable {
    let title: String
    let fullName: String
    let remoteOnly: Bool
    let cloud: Bool
    let tag: Bool
    let current: Bool
    var id: String { fullName }

    static func make(refs: [String]) -> [Self] {
        let names = refs.map { $0.hasPrefix("HEAD -> ") ? String($0.dropFirst(8)) : $0 }
        let remoteNames = names.filter { $0.hasPrefix("refs/remotes/") }
        var badges: [Self] = []
        var consumed: Set<String> = []
        for (index, name) in names.enumerated() where !consumed.contains(name) && name != "HEAD" && !(name.hasPrefix("refs/remotes/") && name.hasSuffix("/HEAD")) {
            let isTag = name.hasPrefix("tag: ")
            // %D のリモート名はリモート一覧と同じ短縮名。origin 以外も末尾一致で束ねる。
            let isRemote = name.hasPrefix("refs/remotes/")
            let short = name.replacingOccurrences(of: "tag: refs/tags/", with: "")
                .replacingOccurrences(of: "refs/heads/", with: "").replacingOccurrences(of: "refs/remotes/", with: "")
            let remotes = name.hasPrefix("refs/heads/") ? remoteNames.filter {
                String($0.dropFirst("refs/remotes/".count)).split(separator: "/", maxSplits: 1).last.map(String.init) == short
            } : []
            consumed.formUnion(remotes)
            if isRemote, names.contains("refs/heads/" + short.split(separator: "/", maxSplits: 1).dropFirst().joined(separator: "/")) { continue }
            let text = isRemote ? short.split(separator: "/", maxSplits: 1).dropFirst().joined(separator: "/") : short
            let title = !isTag && text.contains("/") ? "…/" + String(text.split(separator: "/").last ?? "") : text
            let fullNames = ([name] + remotes).map { $0.replacingOccurrences(of: "refs/heads/", with: "").replacingOccurrences(of: "refs/remotes/", with: "") }
            badges.append(.init(title: title, fullName: fullNames.joined(separator: " · "), remoteOnly: isRemote,
                                cloud: isRemote || !remotes.isEmpty, tag: isTag, current: refs[index].hasPrefix("HEAD -> ")))
        }
        return badges
    }
}

enum GitRepositoryAction: Equatable, Sendable {
    case switchBranch(String)
    case createBranch(name: String, start: String, switchTo: Bool)
    case renameBranch(old: String, new: String)
    case deleteBranch(String, force: Bool)
    case checkoutRemote(String)
    case fetch
    case stash(String)
    case applyStash(String)
    case popStash(String)
    case dropStash(String)

    var changesWorkingTree: Bool {
        switch self {
        case .switchBranch, .checkoutRemote, .stash, .applyStash, .popStash: true
        case .createBranch(_, _, let switchTo): switchTo
        default: false
        }
    }
    var needsDestructiveConfirmation: Bool {
        switch self { case .deleteBranch, .dropStash, .popStash: true; default: false }
    }
    func needsConfirmation(runningSession: Bool) -> Bool {
        needsDestructiveConfirmation || changesWorkingTree && runningSession
    }
}
