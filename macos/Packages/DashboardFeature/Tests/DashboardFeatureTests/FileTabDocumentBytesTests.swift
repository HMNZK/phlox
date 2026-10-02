import Foundation
import Testing
@testable import DashboardFeature

@MainActor
struct FileTabDocumentBytesTests {
    @Test
    func detectsCanonicallyEquivalentDraftAsDirty() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("\u{e9}".utf8).write(to: root.appendingPathComponent("a.txt"))
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "e\u{301}"
        #expect(document.isDirty)
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: root.appendingPathComponent("a.txt")) == Data("e\u{301}".utf8))
    }

    @Test
    func detectsCanonicallyEquivalentDiskChangeAsConflict() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("\u{e9}".utf8).write(to: file)
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        try Data("e\u{301}".utf8).write(to: file)
        document.draft = "変更"
        #expect(try await document.save() == .conflictDetected)
        #expect(try Data(contentsOf: file) == Data("e\u{301}".utf8))
    }

    @Test(arguments: ["先頭\r\n末尾", "一行\r\n二行\n三行\r四行\n", "末尾改行なし", ""])
    func preservesBOMAndLineEndings(text: String) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        let bom = Data([0xef, 0xbb, 0xbf])
        let original = bom + Data(text.utf8)
        try original.write(to: file)
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        #expect(document.draft.utf8.elementsEqual(text.utf8))
        #expect(document.bom == bom)
        #expect(!document.isDirty)
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == original)
        document.draft += "追記"
        try await document.overwrite()
        #expect(try Data(contentsOf: file) == bom + Data((text + "追記").utf8))
    }

    @Test
    func reportsRejectedDataWithoutMakingItEditable() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(Data, FileTabDocument.LoadState)] = [
            (Data(repeating: 0x61, count: 1_000_001), .tooLarge),
            (Data([0x61, 0, 0x62]), .binary),
            (Data([0xff]), .loadFailed),
        ]
        for (bytes, expected) in cases {
            try bytes.write(to: root.appendingPathComponent("a.txt"))
            let document = FileTabDocument(path: "a.txt", root: root.path)
            await document.loadIfNeeded()
            #expect(document.loadState == expected)
            #expect(!document.isLoaded)
            #expect(document.loadedDiskBytes.isEmpty)
            #expect(try await document.save() == .conflictDetected)
            #expect(try Data(contentsOf: root.appendingPathComponent("a.txt")) == bytes)
        }
    }

    @Test
    func repeatedLoadsDoNotReplaceDraft() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("元".utf8).write(to: root.appendingPathComponent("a.txt"))
        let document = FileTabDocument(path: "a.txt", root: root.path)
        async let first: Void = document.loadIfNeeded()
        async let second: Void = document.loadIfNeeded()
        _ = await (first, second)
        document.draft = "下書き"
        await document.loadIfNeeded()
        #expect(document.draft == "下書き")
        #expect(document.isDirty)
    }
}

func makeFileTabTestRoot() throws -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let root = packageRoot.appendingPathComponent(".build/file-document-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
