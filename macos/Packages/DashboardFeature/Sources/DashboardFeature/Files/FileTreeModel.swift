import Foundation
import Observation

@MainActor
@Observable
final class FileTreeModel {
    static func model(for root: String, in models: [String: FileTreeModel]) -> FileTreeModel {
        models[root] ?? FileTreeModel(root: root)
    }

    let root: String
    private(set) var childrenByDir: [String: [FileTreeEntry]] = [:]
    private(set) var expanded: Set<String> = []
    private(set) var errorsByDir: [String: String] = [:]
    private(set) var omittedByDir: [String: Int] = [:]
    private(set) var loading: Set<String> = []
    private(set) var branch = ""
    private let loader: FileTreeLoader
    private let readBranch: @Sendable () async -> String
    private var generations: [String: UUID] = [:]
    private var branchGeneration = UUID()

    init(root: String, loader: FileTreeLoader? = nil, readBranch: (@Sendable () async -> String)? = nil) {
        self.root = root
        self.loader = loader ?? FileTreeLoader(root: root)
        self.readBranch = readBranch ?? {
            await WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root), fixedRoot: true).branchLabel()
        }
    }

    var rows: [FileTreeRows.Row] {
        FileTreeRows.visibleRows(childrenByDir: childrenByDir, expanded: expanded)
    }

    func expand(_ path: String) async {
        guard rows.contains(where: { $0.id == path && $0.entry.canExpand }) else { return }
        expanded.insert(path)
        await load(path)
    }

    func collapse(_ path: String) { expanded.remove(path) }

    func refresh() async {
        let generation = UUID()
        branchGeneration = generation
        async let label = readBranch()
        async let directories: Void = refreshDirectories()
        let value = await label
        if branchGeneration == generation { branch = value }
        await directories
    }

    private func refreshDirectories() async {
        await withTaskGroup(of: Void.self) { group in
            for path in expanded.union([""]) {
                group.addTask { await self.load(path) }
            }
        }
    }

    func fileSaved(root: String, relativePath: String) async {
        guard self.root == root else { return }
        await load(FileTreeRows.parent(of: relativePath))
    }

    func load(_ path: String, refresh: Bool = false) async {
        let generation = UUID()
        generations[path] = generation
        loading.insert(path)
        defer { if generations[path] == generation { loading.remove(path) } }
        do {
            guard let listing = try await loader.children(of: path, refresh: refresh),
                  generations[path] == generation else { return }
            childrenByDir[path] = listing.entries
            omittedByDir[path] = listing.omittedCount
            errorsByDir[path] = nil
        } catch {
            guard generations[path] == generation else { return }
            childrenByDir[path] = nil
            omittedByDir[path] = nil
            errorsByDir[path] = FileTreeLoader.failureReason(error)
        }
    }
}
