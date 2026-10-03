import Foundation

enum FileTreeRows {
    static func openPath(selected: ChildTab, viewMode: ViewMode, commonTerminalSelected: Bool) -> String? {
        guard viewMode == .single, !commonTerminalSelected,
              case .file(let path) = selected else { return nil }
        return path
    }

    static func selection(openPath: String?, selectedPath: String?, rows: [Row]) -> String? {
        if let openPath, rows.contains(where: { $0.isOpen(openPath) }) { return openPath }
        return visibleSelection(selectedPath, rows: rows)
    }

    struct Row: Identifiable, Equatable {
        let entry: FileTreeEntry
        let depth: Int
        var id: String { entry.relativePath }
        func isOpen(_ path: String?) -> Bool { entry.canOpen && id == path }
    }

    enum Key { case up, down, right, left, activate }
    enum Action: Equatable {
        case select(String), expand(String), collapse(String), open(String), explainBlocked(String)
    }

    static func visibleRows(childrenByDir: [String: [FileTreeEntry]], expanded: Set<String>) -> [Row] {
        var rows: [Row] = []
        func append(_ directory: String, depth: Int) {
            for entry in childrenByDir[directory] ?? [] {
                rows.append(Row(entry: entry, depth: depth))
                if entry.canExpand, expanded.contains(entry.relativePath) {
                    append(entry.relativePath, depth: depth + 1)
                }
            }
        }
        append("", depth: 0)
        return rows
    }

    static func action(for path: String?, key: Key, rows: [Row], expanded: Set<String>) -> Action? {
        guard let row = rows.first(where: { $0.id == path }) else { return nil }
        switch key {
        case .up, .down:
            guard let index = rows.firstIndex(where: { $0.id == path }) else { return nil }
            let next = key == .up ? index - 1 : index + 1
            return rows.indices.contains(next) ? .select(rows[next].id) : nil
        case .activate:
            if row.entry.kind == .symlinkOutsideRoot { return .explainBlocked(row.id) }
            if row.entry.canExpand {
                return expanded.contains(row.id) ? .collapse(row.id) : .expand(row.id)
            }
            return row.entry.canOpen ? .open(row.id) : nil
        case .right:
            guard row.entry.canExpand else { return nil }
            if !expanded.contains(row.id) { return .expand(row.id) }
            if let child = rows.first(where: { parent(of: $0.id) == row.id }) { return .select(child.id) }
            return nil
        case .left:
            if row.entry.canExpand, expanded.contains(row.id) { return .collapse(row.id) }
            let parent = parent(of: row.id)
            return parent.isEmpty ? nil : .select(parent)
        }
    }

    static func finishedDirectories(after index: Int, rows: [Row]) -> [String] {
        guard rows.indices.contains(index) else { return [] }
        let nextDepth = rows.indices.contains(index + 1) ? rows[index + 1].depth : 0
        var path = parent(of: rows[index].id)
        var depth = rows[index].depth
        var result: [String] = []
        while depth > nextDepth, !path.isEmpty {
            result.append(path)
            path = parent(of: path)
            depth -= 1
        }
        return result
    }

    static func parent(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    static func visibleSelection(_ path: String?, rows: [Row]) -> String? {
        guard var path else { return nil }
        let visible = Set(rows.map(\.id))
        while !path.isEmpty {
            if visible.contains(path) { return path }
            path = parent(of: path)
        }
        return nil
    }
}
