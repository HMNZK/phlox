import Foundation

struct FileTreeEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case directory, file, symlinkToDirectory, symlinkOutsideRoot, symlinkToFile, unavailable
    }

    let relativePath: String
    let name: String
    let kind: Kind
    var resolvedPath: String? = nil
    var unavailableReason: String? = nil
    var outsideTargetIsDirectory = false
    var id: String { relativePath }
    var canExpand: Bool { kind == .directory }
    var canOpen: Bool { kind == .file || kind == .symlinkToFile }
    var isFolder: Bool { kind == .directory || kind == .symlinkToDirectory || outsideTargetIsDirectory }

    var linkDestination: String? {
        guard let resolvedPath else { return nil }
        return "→ " + (resolvedPath as NSString).lastPathComponent
    }

    var help: String {
        let destination = resolvedPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
        if kind == .symlinkOutsideRoot {
            return "作業ツリーの外を指しているため開けません。" + (destination.map { "→ \($0)" } ?? "")
        }
        if kind == .unavailable { return kindLabel }
        return destination ?? name
    }

    func finderURL(root: String) -> URL {
        if kind == .symlinkOutsideRoot, let resolvedPath { return URL(fileURLWithPath: resolvedPath) }
        return URL(fileURLWithPath: root).appendingPathComponent(relativePath)
    }

    var kindLabel: String {
        switch kind {
        case .directory: "フォルダ"
        case .file: "ファイル"
        case .symlinkToDirectory: "フォルダへのリンク、展開できません"
        case .symlinkToFile: "ファイルへのリンク"
        case .symlinkOutsideRoot: "作業ツリーの外を指すリンク、開けません"
        case .unavailable: "開けません。\(unavailableReason ?? "ファイルの情報を取得できません。")"
        }
    }
}

actor FileTreeLoader {
    struct Listing: Equatable, Sendable {
        let entries: [FileTreeEntry]
        let omittedCount: Int
    }

    private let root: URL
    private let read: @Sendable (URL, String) async throws -> Listing
    private var completed: Set<UUID> = []
    private var pending: [String: (id: UUID, task: Task<Listing, Error>)] = [:]

    init(root: String, read: @escaping @Sendable (URL, String) async throws -> Listing = { root, path in
        try FileTreeLoader.readDirectory(root: root, path: path)
    }) {
        self.root = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        self.read = read
    }

    /// 更新で置き換えられた要求は、成功・失敗とも画面へ返さない。
    func children(of path: String, refresh: Bool = false) async throws -> Listing? {
        let request: (id: UUID, task: Task<Listing, Error>)
        if !refresh, let existing = pending[path], !completed.contains(existing.id) {
            request = existing
        } else {
            let root = root
            let read = read
            request = (UUID(), Task.detached { try await read(root, path) })
            if let old = pending[path] { completed.remove(old.id) }
            pending[path] = request
        }
        let result = await request.task.result
        guard pending[path]?.id == request.id else { return nil }
        // 待機中の要求だけ集約し、次の呼び出しはディスクを読み直す。
        completed.insert(request.id)
        return try result.get()
    }

    nonisolated static func readDirectory(root: URL, path: String) throws -> Listing {
        let directory = try WorkingTreeService.relativeURL(for: path, relativeTo: root, allowRoot: true)
        _ = try WorkingTreeService.containedURL(directory, under: root, allowRoot: true)
        // 途中のフォルダがリンクへ置き換わった場合も展開しない。
        var ancestor = root
        for component in path.split(separator: "/") {
            ancestor.appendPathComponent(String(component))
            if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw WorkingTreeServiceError.notRegularFile(ancestor.path)
            }
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        )
        let entries = urls.filter { ![".git", ".DS_Store"].contains($0.lastPathComponent) }.map { url in
            var entry = FileTreeEntry(
                relativePath: path.isEmpty ? url.lastPathComponent : path + "/" + url.lastPathComponent,
                name: url.lastPathComponent, kind: .unavailable
            )
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                let target: URL
                do {
                    target = try WorkingTreeService.containedURL(url, under: root, allowRoot: true)
                } catch WorkingTreeServiceError.outsideRoot(let resolvedPath) {
                    let target = URL(fileURLWithPath: resolvedPath)
                    return FileTreeEntry(relativePath: entry.relativePath, name: entry.name,
                                         kind: .symlinkOutsideRoot, resolvedPath: resolvedPath,
                                         outsideTargetIsDirectory: (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
                }
                let isLink = values.isSymbolicLink == true
                if isLink { entry.resolvedPath = target.path }
                guard FileManager.default.fileExists(atPath: target.path) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                let targetValues = isLink
                    ? try target.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) : values
                guard targetValues.isDirectory == true || targetValues.isRegularFile == true else {
                    throw WorkingTreeServiceError.notRegularFile(target.path)
                }
                let kind: FileTreeEntry.Kind = targetValues.isDirectory == true
                    ? (isLink ? .symlinkToDirectory : .directory) : (isLink ? .symlinkToFile : .file)
                return FileTreeEntry(relativePath: entry.relativePath, name: entry.name,
                                     kind: kind, resolvedPath: entry.resolvedPath)
            } catch {
                entry.unavailableReason = failureReason(error)
                return entry
            }
        }.sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) : order == .orderedAscending
        }
        return Listing(entries: Array(entries.prefix(5_000)), omittedCount: max(0, entries.count - 5_000))
    }

    nonisolated static func failureReason(_ error: Error) -> String {
        if let error = error as? WorkingTreeServiceError {
            switch error {
            case .outsideRoot: return "作業ツリーの外を指しているため開けません。"
            case .notRegularFile: return "通常のファイルやフォルダではないため開けません。"
            case .invalidRelativePath: return "ファイルのパスが不正です。"
            case .missingRoot: return "作業フォルダが見つかりません。"
            default: return "ファイルの情報を取得できません。"
            }
        }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: error.code) {
            case .fileReadNoPermission: return "アクセス権がないため読み込めません。"
            case .fileReadNoSuchFile, .fileNoSuchFile: return "ファイルまたはフォルダが見つかりません。"
            default: break
            }
        }
        return "ファイルまたはフォルダを読み込めません。"
    }
}
