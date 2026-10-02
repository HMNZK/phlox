import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@MainActor
struct FileTabDocumentLifecycleTests {
    @Test
    func replacingResolvedRootWithSymlinkRejectsSaving() async throws {
        let directory = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first"), second = directory.appendingPathComponent("second")
        for root in [first, second] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("元".utf8).write(to: root.appendingPathComponent("a.txt"))
        }
        let document = FileTabDocument(path: "a.txt", root: first.path)
        await document.loadIfNeeded()
        try FileManager.default.moveItem(at: first, to: directory.appendingPathComponent("former"))
        try FileManager.default.createSymbolicLink(at: first, withDestinationURL: second)
        document.draft = "変更"
        await #expect(throws: WorkingTreeServiceError.self) { try await document.save() }
        #expect(try Data(contentsOf: second.appendingPathComponent("a.txt")) == Data("元".utf8))
    }

    @Test
    func rootSymlinkReplacementDoesNotRedirectSaving() async throws {
        let directory = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first"), second = directory.appendingPathComponent("second")
        let link = directory.appendingPathComponent("root")
        for root in [first, second] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("元".utf8).write(to: root.appendingPathComponent("a.txt"))
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        let document = FileTabDocument(path: "a.txt", root: link.path)
        await document.loadIfNeeded()
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        document.draft = "変更"
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: first.appendingPathComponent("a.txt")) == Data("変更".utf8))
        #expect(try Data(contentsOf: second.appendingPathComponent("a.txt")) == Data("元".utf8))
    }

    @Test
    func invalidationRejectsEditingSavingAndOverwrite() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("元".utf8).write(to: file)
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "下書き"
        document.invalidate()
        document.draft = "失効後の確定・undo"
        #expect(document.draft == "下書き")
        await #expect(throws: FileTabDocument.DocumentError.invalidated) { try await document.save() }
        await #expect(throws: FileTabDocument.DocumentError.invalidated) { try await document.overwrite() }
        #expect(try Data(contentsOf: file) == Data("元".utf8))
    }

    @Test
    func dirtyDocumentIsNotAutomaticallyReplacedWhenRootChanges() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("元".utf8).write(to: root.appendingPathComponent("a.txt"))
        let files = FileTabDocuments()
        let sessionID = SessionID()
        let old = files.document(for: sessionID, path: "a.txt", root: root.path)
        await old.loadIfNeeded()
        old.draft = "下書き"
        #expect(files.document(for: sessionID, path: "a.txt", root: root.path + "/other") === old)
        #expect(files.document(for: sessionID, path: "a.txt", workingDirectory: root.path + "/other") === old)
        #expect(!old.invalidated)
        await files.removeAll(for: sessionID)
        #expect(old.invalidated)
        #expect(files.documents().isEmpty)
    }

    @Test
    func queuedSavesUsePreviousSuccessfulSaveAsBaseline() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("元".utf8).write(to: file)
        let document = FileTabDocument(path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "一回目"
        let first = try document.enqueueSave(overwrite: false)
        document.draft = "二回目"
        let second = try document.enqueueSave(overwrite: false)
        #expect(document.hasPendingSaves)
        #expect(try await first.value == .saved)
        #expect(try await second.value == .saved)
        await document.waitForPendingSaves()
        #expect(try Data(contentsOf: file) == Data("二回目".utf8))
        #expect(!document.isDirty)
    }

    @Test
    func removalWaitsForAcceptedSavesAndInvalidatesReferences() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("元".utf8).write(to: root.appendingPathComponent("a.txt"))
        let files = FileTabDocuments()
        let sessionID = SessionID()
        let document = files.document(for: sessionID, path: "a.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft = "下書き"
        let saving = try document.enqueueSave(overwrite: false)
        #expect(document.hasPendingSaves)
        document.invalidate()
        #expect(!document.invalidated)
        #expect(throws: FileTabDocument.DocumentError.invalidated) { try document.enqueueSave(overwrite: false) }
        await files.remove(for: sessionID, path: "a.txt")
        #expect(try await saving.value == .saved)
        #expect(try Data(contentsOf: root.appendingPathComponent("a.txt")) == Data("下書き".utf8))
        #expect(document.invalidated)
        #expect(!document.hasPendingSaves)
        #expect(files.existing(for: sessionID, path: "a.txt") == nil)
    }
}
