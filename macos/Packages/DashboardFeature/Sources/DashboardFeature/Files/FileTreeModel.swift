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
    var edit: FileTreeEdit?
    var operationFailure: FileTreeFailure?
    private(set) var operating = false
    private(set) var operationSelection: String?
    private(set) var lastRename: (from: String, to: String)?
    private let operations: FileTreeOperations
    private let caseSensitiveNames: Bool

    init(root: String, loader: FileTreeLoader? = nil, readBranch: (@Sendable () async -> String)? = nil) {
        self.root = root
        self.operations = FileTreeOperations(root: root)
        self.caseSensitiveNames = (try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames ?? true
        self.loader = loader ?? FileTreeLoader(root: root)
        self.readBranch = readBranch ?? {
            await WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root), fixedRoot: true).branchLabel()
        }
    }

    var rows: [FileTreeRows.Row] {
        var children = childrenByDir
        if let edit, edit.isNew {
            let entry = FileTreeEntry(relativePath: edit.rowID, name: "", kind: edit.folder ? .directory : .file)
            let index = edit.folder ? 0 : (children[edit.parent]?.firstIndex { !$0.isFolder } ?? children[edit.parent]?.count ?? 0)
            children[edit.parent, default: []].insert(entry, at: index)
        }
        return FileTreeRows.visibleRows(childrenByDir: children, expanded: expanded)
    }

    func beginCreate(at entry: FileTreeEntry?, folder: Bool) async {
        guard !operating, entry?.canCreate != false else { return }
        operationFailure = nil
        let parent: String
        if let entry, entry.kind == .symlinkToDirectory, let resolved = entry.resolvedPath {
            guard let path = resolved == root ? "" : FileTabOpening.relativePath(of: URL(fileURLWithPath: resolved), under: root) else { return }
            parent = path
        } else { parent = entry.map { $0.canExpand ? $0.relativePath : FileTreeRows.parent(of: $0.relativePath) } ?? "" }
        var ancestor = parent
        while !ancestor.isEmpty {
            expanded.insert(ancestor)
            await load(ancestor)
            ancestor = FileTreeRows.parent(of: ancestor)
        }
        await load(parent)
        edit = FileTreeEdit(parent: parent, folder: folder)
    }

    func beginRename(_ entry: FileTreeEntry) {
        guard !operating, entry.canModify else { return }
        operationFailure = nil
        edit = FileTreeEdit(parent: FileTreeRows.parent(of: entry.relativePath), folder: entry.isFolder,
                            originalPath: entry.relativePath, name: entry.name)
    }

    func updateName(_ name: String) {
        guard var edit else { return }
        edit.name = name
        edit.error = nameError(edit)?.key
        self.edit = edit
    }

    func submitEdit() -> FileTreeOperation? {
        guard var edit, !operating else { return nil }
        edit.submitted = true
        edit.error = nameError(edit)?.key
        self.edit = edit
        guard edit.error == nil else { return nil }
        if let path = edit.originalPath { return .rename(path: path, name: edit.name) }
        return .create(parent: edit.parent, name: edit.name, folder: edit.folder)
    }

    private func nameError(_ edit: FileTreeEdit) -> FileTreeNameError? {
        if let error = FileTreeOperations.nameError(edit.name, siblings: childrenByDir[edit.parent] ?? [],
            renaming: edit.originalPath, submitted: edit.submitted, caseSensitive: caseSensitiveNames) { return error }
        if !edit.name.isEmpty, (omittedByDir[edit.parent] ?? 0) > 0 {
            do {
                if let sibling = try FileTreeOperations.omittedSibling(name: edit.name, parent: edit.parent, root: root, renaming: edit.originalPath) {
                    return FileTreeNameError(key: sibling.isFolder ? "同じ名前のフォルダがあります" : "同じ名前のファイルがあります")
                }
            } catch { return FileTreeNameError(key: FileTreeFailure(operationKey: "", error: error).reason) }
        }
        return nil
    }

    func countItems(in path: String) async throws -> FileTreeItemCount { try await operations.countItems(in: path) }

    @discardableResult
    func perform(_ operation: FileTreeOperation) async -> Result<String?, Error> {
        guard !operating else { return .failure(CocoaError(.fileWriteUnknown)) }
        operating = true
        operationFailure = nil
        lastRename = nil
        let previousRows = rows.filter { $0.id != edit?.rowID }
        let deletedIndex: Int?
        if case .trash(let path) = operation { deletedIndex = previousRows.firstIndex { $0.id == path } }
        else { deletedIndex = nil }
        defer { operating = false }
        let result: Result<String?, Error>
        do { result = .success(try await operations.execute(operation)) }
        catch { result = .failure(error) }
        edit = nil
        let revealed: String?
        if case .success(let path) = result { revealed = path } else { revealed = nil }
        await load(operation.parent, refresh: true, revealing: revealed)
        switch result {
        case .success(let path):
            if case .rename(let old, _) = operation, let path {
                lastRename = (old, path)
                expanded = Set(expanded.map { FileTreeOperations.renamedPath($0, from: old, to: path) ?? $0 })
                for directory in Array(childrenByDir.keys) where FileTreeOperations.renamedPath(directory, from: old, to: path) != nil {
                    childrenByDir[directory] = nil
                }
                for directory in expanded.sorted() { await load(directory, refresh: true) }
            }
            if case .trash(let old) = operation {
                expanded = expanded.filter { FileTreeOperations.renamedPath($0, from: old, to: old) == nil }
                operationSelection = rows.isEmpty ? nil : rows[min(deletedIndex ?? 0, rows.count - 1)].id
            } else { operationSelection = path }
        case .failure(let error): operationFailure = FileTreeFailure(operationKey: operation.failureKey, error: error)
        }
        return result
    }

    func expand(_ path: String) async {
        guard rows.contains(where: { $0.id == path && $0.entry.canExpand }) else { return }
        expanded.insert(path)
        await load(path)
    }

    func collapse(_ path: String) { expanded.remove(path) }

    func refresh() async {
        operationFailure = nil
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

    func load(_ path: String, refresh: Bool = false, revealing: String? = nil) async {
        let generation = UUID()
        generations[path] = generation
        loading.insert(path)
        defer { if generations[path] == generation { loading.remove(path) } }
        do {
            let target = revealing ?? operationSelection.flatMap { FileTreeRows.parent(of: $0) == path ? $0 : nil }
            guard let listing = try await loader.children(of: path, refresh: refresh, revealing: target),
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
