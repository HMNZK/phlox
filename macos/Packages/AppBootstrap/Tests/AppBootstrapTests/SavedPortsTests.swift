import Foundation
import Testing
@testable import AppBootstrap

@Suite struct SavedPortsTests {
    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-saved-ports-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("ports.json")
    }

    @Test func saveThenLoadRoundTripsValues() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let ports = SavedPorts(hookPort: 57398, controlPort: 57399)
        try ports.save(to: url)

        #expect(SavedPorts.load(from: url) == ports)
    }

    @Test func saveCreatesIntermediateDirectories() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        try SavedPorts(hookPort: 1, controlPort: 2).save(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func loadReturnsNilWhenFileIsMissing() {
        #expect(SavedPorts.load(from: makeTempFileURL()) == nil)
    }

    @Test func loadReturnsNilForCorruptedJSON() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{not json".utf8).write(to: url)

        #expect(SavedPorts.load(from: url) == nil)
    }

    @Test func loadReturnsNilWhenKeysAreMissing() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"hookPort": 57398}"#.utf8).write(to: url)

        #expect(SavedPorts.load(from: url) == nil)
    }
}
