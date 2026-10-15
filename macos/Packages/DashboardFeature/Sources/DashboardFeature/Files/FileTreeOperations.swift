import Foundation
import CoreFoundation
import Darwin

enum FileTreeOperation: Equatable, Sendable {
    case create(parent: String, name: String, folder: Bool)
    case rename(path: String, name: String)
    case trash(path: String)

    var parent: String {
        switch self {
        case .create(let parent, _, _): parent
        case .rename(let path, _), .trash(let path): FileTreeRows.parent(of: path)
        }
    }
    var failureKey: String {
        switch self {
        case .create: "作成できませんでした: %@"
        case .rename: "名前を変更できませんでした: %@"
        case .trash: "ゴミ箱に入れられませんでした: %@"
        }
    }
}

struct FileTreeNameError: Error, Equatable, Sendable {
    let key: String
}

struct FileTreeItemCount: Equatable, Sendable {
    var folders = 0
    var files = 0
    var limited = false
    var total: Int { folders + files }
}

actor FileTreeOperations {
    let root: URL
    init(root: String) { self.root = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL }

    nonisolated static func nameError(_ name: String, siblings: [FileTreeEntry], renaming: String? = nil,
                                     submitted: Bool = true, caseSensitive: Bool = true) -> FileTreeNameError? {
        if name.isEmpty { return submitted ? .init(key: "名前を入力してください") : nil }
        if name.contains("/") { return .init(key: "名前に / は使えません") }
        if name == "." || name == ".." { return .init(key: "「.」と「..」は名前に使えません") }
        if name.utf8.contains(0) { return .init(key: "名前に NUL は使えません") }
        if FileTreeLoader.excludedNames.contains(name) { return .init(key: "この名前はファイル操作の対象外です") }
        if let entry = siblings.first(where: {
            $0.relativePath != renaming && ($0.name == name || (!caseSensitive && $0.name.caseInsensitiveCompare(name) == .orderedSame))
        }) {
            return .init(key: entry.isFolder ? "同じ名前のフォルダがあります" : "同じ名前のファイルがあります")
        }
        return nil
    }

    nonisolated static func renamedPath(_ path: String, from old: String, to new: String) -> String? {
        if path == old { return new }
        guard path.hasPrefix(old + "/") else { return nil }
        return new + path.dropFirst(old.count)
    }

    /// 表示上限で省略された同名の項目も、内容を読まずに検査する。
    nonisolated static func omittedSibling(name: String, parent: String, root: String, renaming: String?) throws -> FileTreeEntry? {
        let rootURL = URL(fileURLWithPath: root)
        let path = parent.isEmpty ? name : parent + "/" + name
        let url = try WorkingTreeService.relativeURL(for: path, relativeTo: rootURL)
        _ = try WorkingTreeService.containedURL(url, under: rootURL)
        var destination = stat()
        guard lstat(url.path, &destination) == 0 else {
            if errno == ENOENT { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        if let renaming, (renaming as NSString).lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
            var original = stat()
            if lstat(rootURL.appendingPathComponent(renaming).path, &original) == 0,
               original.st_dev == destination.st_dev, original.st_ino == destination.st_ino { return nil }
        }
        var directory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        return FileTreeEntry(relativePath: path, name: name, kind: directory.boolValue ? .directory : .file)
    }

    nonisolated static func nameSelection(_ name: String, folder: Bool) -> NSRange {
        let text = name as NSString
        let ext = text.pathExtension
        let length = folder || name.hasPrefix(".") || ext.isEmpty ? text.length : text.length - (ext as NSString).length - 1
        return NSRange(location: 0, length: length)
    }

    func countItems(in path: String) throws -> FileTreeItemCount {
        let url = try checkedURL(path)
        var result = FileTreeItemCount()
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        while let child = enumerator.nextObject() as? URL {
            if result.total == 1_000 { result.limited = true; break }
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            if values.isDirectory == true && values.isSymbolicLink != true { result.folders += 1 }
            else { result.files += 1 }
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    func execute(_ operation: FileTreeOperation) throws -> String? {
        let parent = try checkedURL(operation.parent, allowRoot: true)
        // 親を no-follow で固定し、作成・名前変更の間のリンク差し替えを追わない。
        let descriptor = try openParent(operation.parent)
        defer { close(descriptor) }
        switch operation {
        case .create(_, let name, let folder):
            try validate(name, parent: operation.parent)
            _ = try checkedURL(operation.parent, allowRoot: true)
            if folder {
                guard mkdirat(descriptor, name, 0o755) == 0 else { throw posixError() }
            } else {
                let file = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
                guard file >= 0 else { throw posixError() }
                close(file)
            }
            return joined(operation.parent, name)
        case .rename(let path, let name):
            let source = try checkedURL(path)
            try validate(name, parent: operation.parent, renaming: path)
            if source.lastPathComponent.utf8.elementsEqual(name.utf8) { return path }
            let destination = parent.appendingPathComponent(name)
            _ = try WorkingTreeService.containedURL(destination, under: root)
            // APFS の大文字小文字だけの変更は同じ inode と確認してから通常の rename。
            let sameItem = sameFile(source, destination)
            _ = try checkedURL(path)
            let status = sameItem
                ? renameat(descriptor, source.lastPathComponent, descriptor, name)
                : renameatx_np(descriptor, source.lastPathComponent, descriptor, name, UInt32(RENAME_EXCL))
            guard status == 0 else { throw posixError() }
            return joined(operation.parent, name)
        case .trash(let path):
            let source = try checkedURL(path)
            // file-reference URL は親のパスがリンクへ差し替わっても同じ項目を指す。
            let reference = try Self.fileReference(for: source)
            _ = try checkedURL(path)
            try trash(reference: reference)
            return nil
        }
    }

    nonisolated static func fileReference(for source: URL) throws -> String {
        var error: Unmanaged<CFError>?
        guard let reference = CFURLCreateFileReferenceURL(nil, source as CFURL, &error)?.takeRetainedValue() else {
            if let error { throw error.takeRetainedValue() }
            throw CocoaError(.fileNoSuchFile)
        }
        // Swift URL への変換は参照を元のパスに戻すため、識別子をそのまま保持する。
        return CFURLGetString(reference) as String
    }

    nonisolated static func filePath(for reference: String) throws -> URL {
        var error: Unmanaged<CFError>?
        let url = CFURLCreateWithString(nil, reference as CFString, nil)
        guard let current = CFURLCreateFilePathURL(nil, url, &error)?.takeRetainedValue() else {
            if let error { throw error.takeRetainedValue() }
            throw CocoaError(.fileNoSuchFile)
        }
        return current as URL
    }

    func trash(reference: String) throws {
        let current = try Self.filePath(for: reference)
        _ = try WorkingTreeService.containedURL(current, under: root)
        // ponytail: 包含検査から直後の同期 trashItem 呼び出しまでの外部移動は原子的に防げない。OS が原子的な API を提供したら置き換える。
        try FileManager.default.trashItem(at: current, resultingItemURL: nil)
    }

    private func validate(_ name: String, parent: String, renaming: String? = nil) throws {
        let listing = try FileTreeLoader.readDirectory(root: root, path: parent)
        if let error = Self.nameError(name, siblings: listing.entries, renaming: renaming) { throw error }
        let destination = try checkedURL(joined(parent, name))
        if FileManager.default.fileExists(atPath: destination.path),
           renaming.map({ sameFile(root.appendingPathComponent($0), destination) }) != true {
            let folder = try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            throw FileTreeNameError(key: folder ? "同じ名前のフォルダがあります" : "同じ名前のファイルがあります")
        }
    }

    private func checkedURL(_ path: String, allowRoot: Bool = false) throws -> URL {
        guard root.resolvingSymlinksInPath().path.utf8.elementsEqual(root.path.utf8) else {
            throw WorkingTreeServiceError.outsideRoot(root.path)
        }
        let url = try WorkingTreeService.relativeURL(for: path, relativeTo: root, allowRoot: allowRoot)
        _ = try WorkingTreeService.containedURL(url, under: root, allowRoot: allowRoot)
        var ancestor = root
        for component in path.split(separator: "/").dropLast() {
            ancestor.appendPathComponent(String(component))
            if try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw WorkingTreeServiceError.outsideRoot(ancestor.path)
            }
        }
        return url
    }

    private func sameFile(_ a: URL, _ b: URL) -> Bool {
        var first = stat(), second = stat()
        return lstat(a.path, &first) == 0 && lstat(b.path, &second) == 0
            && first.st_dev == second.st_dev && first.st_ino == second.st_ino
    }
    private func openParent(_ path: String) throws -> Int32 {
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw posixError() }
        for component in path.split(separator: "/") {
            let child = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            let error = child < 0 ? posixError() : nil
            close(descriptor)
            if let error { throw error }
            descriptor = child
        }
        return descriptor
    }
    private func joined(_ parent: String, _ name: String) -> String { parent.isEmpty ? name : parent + "/" + name }
    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
