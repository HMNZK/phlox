import Foundation
import Testing
@testable import DashboardFeature

@Suite("ファイルアクセスの包含確認とバイト保存")
struct WorkingTreeContainmentTests {
    private func directory() throws -> URL {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = package.appendingPathComponent(".build/phlox-containment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("内側の symlink は読み書きでき、外側と同じ接頭辞の兄弟は拒否する")
    func symlinkContainment() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sibling = URL(fileURLWithPath: root.path + "-sibling")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try Data("内側".utf8).write(to: root.appendingPathComponent("inside.txt"))
        try Data("外側".utf8).write(to: sibling.appendingPathComponent("outside.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("internal"), withDestinationURL: root.appendingPathComponent("inside.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("external"), withDestinationURL: sibling.appendingPathComponent("outside.txt"))
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        #expect(try await service.fileContents("internal") == "内側")
        #expect(try await service.save(path: "internal", data: Data("変更".utf8), expectedDiskBytes: Data("内側".utf8)) == .saved)
        #expect(try Data(contentsOf: root.appendingPathComponent("inside.txt")) == Data("変更".utf8))
        for path in ["external", "internal/../external", "../outside.txt", "/outside.txt"] {
            await #expect(throws: (any Error).self) { try await service.fileData(path) }
            await #expect(throws: (any Error).self) { try await service.save(path: path, data: Data(), expectedDiskBytes: nil) }
            #expect(await service.absolutePath(path) == nil)
        }
        #expect(try Data(contentsOf: sibling.appendingPathComponent("outside.txt")) == Data("外側".utf8))
    }

    @Test("ディレクトリとディレクトリへの symlink は編集対象にしない")
    func rejectsDirectories() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("folder"))
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        for path in ["folder", "link"] {
            await #expect(throws: (any Error).self) { try await service.fileData(path) }
            await #expect(throws: (any Error).self) { try await service.save(path: path, data: Data(), expectedDiskBytes: nil) }
            #expect(await service.absolutePath(path) == nil)
        }
    }

    @Test("BOM・混在改行・Unicode の原バイトを往復し、正規等価な外部変更は競合にする")
    func preservesBytesAndDetectsConflict() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("text.txt")
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("é\r\ne\u{301}\n末尾".utf8)
        try bytes.write(to: url)
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        let loaded = try await service.fileData("text.txt")
        let decoded = try WorkingTreeText.decode(loaded)
        #expect(decoded.bom + Data(decoded.text.utf8) == bytes)
        #expect(try await service.save(path: "text.txt", data: bytes, expectedDiskBytes: loaded) == .saved)
        #expect(try Data(contentsOf: url) == bytes)
        let changed = Data([0xEF, 0xBB, 0xBF]) + Data("e\u{301}\r\ne\u{301}\n末尾".utf8)
        try changed.write(to: url)
        #expect(try await service.save(path: "text.txt", data: bytes, expectedDiskBytes: loaded) == .conflict)
        #expect(try Data(contentsOf: url) == changed)
        let currentText = try await service.fileContents("text.txt")
        #expect(try await service.save(path: "text.txt", content: currentText, expectedDiskContent: currentText) == .saved)
        #expect(try Data(contentsOf: url) == changed)
    }

    @Test("固定ルートが消えたら保存せず、親のリポジトリへ戻らない")
    func rejectsMissingRoot() async throws {
        let root = try directory()
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        try Data("元".utf8).write(to: root.appendingPathComponent("text.txt"))
        try FileManager.default.removeItem(at: root)
        await #expect(throws: (any Error).self) { try await service.save(path: "text.txt", data: Data(), expectedDiskBytes: nil) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("共通復号はサイズ・先頭 8 KB の NUL・不正 UTF-8 を拒否する")
    func validatesText() throws {
        #expect(try WorkingTreeText.decode(Data()).text.isEmpty)
        #expect(try WorkingTreeText.decode(Data(repeating: 65, count: 1_000_000)).text.utf8.count == 1_000_000)
        #expect(throws: WorkingTreeTextError.self) { try WorkingTreeText.decode(Data(repeating: 65, count: 1_000_001)) }
        #expect(throws: WorkingTreeTextError.self) { try WorkingTreeText.decode(Data([65, 0])) }
        #expect(throws: WorkingTreeTextError.self) { try WorkingTreeText.decode(Data([0xFF])) }
        #expect(try WorkingTreeText.decode(Data(repeating: 65, count: 8_192) + Data([0])).text.utf8.count == 8_193)
    }

    @Test("上限を超えたファイルは Data 読み込み前に拒否する")
    func rejectsOversizedFile() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 65, count: 1_000_001).write(to: root.appendingPathComponent("large.txt"))
        let service = WorkingTreeService(repositoryRoot: root, fixedRoot: true)
        await #expect(throws: WorkingTreeTextError.self) { try await service.fileData("large.txt") }
    }
}
