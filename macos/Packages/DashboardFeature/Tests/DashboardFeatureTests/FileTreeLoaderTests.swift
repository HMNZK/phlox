import Foundation
import Testing
@testable import DashboardFeature

func fileTreeFixture() throws -> URL {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../../../.build", isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
        .appendingPathComponent("ft-\(UUID().uuidString.prefix(16))", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // 親の実リポジトリを探索しない、Git 管理外の一時フォルダ。
    try Data("gitdir: /存在しないファイルツリー検証用リポジトリ\n".utf8)
        .write(to: root.appendingPathComponent(".git"))
    return root
}

actor FileTreeReadGate {
    private(set) var calls = 0
    private var waits: [Int: CheckedContinuation<FileTreeLoader.Listing, Error>] = [:]
    private var starts: [Int: CheckedContinuation<Void, Never>] = [:]

    func read() async throws -> FileTreeLoader.Listing {
        calls += 1
        let call = calls
        return try await withCheckedThrowingContinuation { continuation in
            waits[call] = continuation
            starts.removeValue(forKey: call)?.resume()
        }
    }

    func started(_ call: Int) async {
        if waits[call] != nil { return }
        await withCheckedContinuation { starts[call] = $0 }
    }

    func finish(_ call: Int, name: String, kind: FileTreeEntry.Kind = .file) {
        waits.removeValue(forKey: call)?.resume(returning: .init(
            entries: [.init(relativePath: name, name: name, kind: kind)], omittedCount: 0
        ))
    }
}

@Suite("ファイルツリーのディスク読み込み")
struct FileTreeLoaderTests {
    @Test("壊れたリンクと特殊ファイルへのリンクがあっても他の行を読める", arguments: ["broken", "fifo", "socket"])
    func unreadableLink(_ type: String) async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(root.path == root.resolvingSymlinksInPath().path)
        try Data().write(to: root.appendingPathComponent("a.txt"))
        let target = root.appendingPathComponent("target")
        var descriptor: Int32 = -1
        defer { if descriptor >= 0 { close(descriptor) } }
        if type == "fifo" {
            try #require(mkfifo(target.path, 0o600) == 0)
        } else if type == "socket" {
            descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            try #require(descriptor >= 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(target.path.utf8) + [0]
            try #require(bytes.count <= MemoryLayout.size(ofValue: address.sun_path))
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            try #require(result == 0)
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path,
                                                   withDestinationPath: "target")
        let listing = try #require(await FileTreeLoader(root: root.path).children(of: ""))
        #expect(listing.entries.contains { $0.name == "a.txt" && $0.canOpen })
        let link = try #require(listing.entries.first { $0.name == "link" })
        #expect(!link.canOpen)
        #expect(!link.canExpand)
        #expect(link.kindLabel.contains("開けません"))
        if type != "broken" {
            #expect(listing.entries.first { $0.name == "target" }?.canOpen == false)
        }
    }

    @Test("自然順・除外・リンクの種類・直下のみの読み込み")
    func listing() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent(".git"))
        for name in ["step-10", "step-2", ".git"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for name in ["a10.txt", "a2.txt", ".DS_Store", ".hidden"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("dir-link").path, withDestinationPath: "step-2")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("file-link").path, withDestinationPath: "a2.txt")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: root.deletingLastPathComponent().path)
        let loader = FileTreeLoader(root: root.path)
        let listing = try #require(await loader.children(of: ""))
        #expect(listing.entries.map(\.name) == ["dir-link", "step-2", "step-10", ".hidden", "a2.txt", "a10.txt", "file-link", "outside"])
        #expect(listing.entries.first { $0.name == "dir-link" }?.canExpand == false)
        #expect(listing.entries.first { $0.name == "file-link" }?.canOpen == true)
        #expect(listing.entries.first { $0.name == "outside" }?.canOpen == false)
        await #expect(throws: WorkingTreeServiceError.self) { try await loader.children(of: "dir-link") }
        await #expect(throws: WorkingTreeServiceError.self) { try await loader.children(of: "outside") }
        await #expect(throws: WorkingTreeServiceError.self) { try await loader.children(of: "../") }
        try Data().write(to: root.appendingPathComponent("new.txt"))
        #expect(try await loader.children(of: "")?.entries.contains { $0.name == "new.txt" } == true)
    }

    @Test("ツリーとファイル読込は同じ包含判定で外側と不正パスを拒否する")
    func sharedContainment() async throws {
        let root = try fileTreeFixture()
        let sibling = try fileTreeFixture()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sibling)
        }
        try Data().write(to: sibling.appendingPathComponent("a.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: sibling)
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        let loader = FileTreeLoader(root: root.path)
        #expect(try WorkingTreeService.containedURL(root, under: root, allowRoot: true) == root)
        #expect(throws: WorkingTreeServiceError.self) {
            try WorkingTreeService.containedURL(root, under: root)
        }
        let listing = try #require(await loader.children(of: ""))
        #expect(listing.entries.first?.kind == .symlinkOutsideRoot)
        for path in ["outside/a.txt", "../a.txt", "/a.txt", "dir/../a.txt", "dir//a.txt", "a\0b"] {
            await #expect(throws: WorkingTreeServiceError.self) { try await loader.children(of: path) }
            await #expect(throws: WorkingTreeServiceError.self) { try await service.fileData(path) }
        }
    }

    @Test("5,000件を表示し残りの数を返す")
    func limit() async throws {
        let root = try fileTreeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<5_002 { try Data().write(to: root.appendingPathComponent("file-\(i)")) }
        let listing = try #require(await FileTreeLoader(root: root.path).children(of: ""))
        #expect(listing.entries.count == 5_000)
        #expect(listing.omittedCount == 2)
        #expect(listing.entries.first?.name == "file-0")
        #expect(listing.entries.last?.name == "file-4999")
    }

    @Test("更新で古い要求の結果を捨てる")
    func generations() async throws {
        let gate = FileTreeReadGate()
        let loader = FileTreeLoader(root: "/", read: { _, _ in try await gate.read() })
        let first = Task { try await loader.children(of: "") }
        await gate.started(1)
        let second = Task { try await loader.children(of: "", refresh: true) }
        await gate.started(2)
        await gate.finish(2, name: "new")
        #expect(try await second.value?.entries.first?.name == "new")
        await gate.finish(1, name: "old")
        #expect(try await first.value == nil)
        #expect(await gate.calls == 2)
    }
}
