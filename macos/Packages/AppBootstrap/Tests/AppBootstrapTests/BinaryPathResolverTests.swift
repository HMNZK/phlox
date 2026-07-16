import Foundation
import Testing
@testable import AppBootstrap

@Suite struct BinaryPathResolverTests {
    /// 一時ディレクトリを作り、テスト終了時に削除する。
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-binary-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func placeExecutable(named name: String, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent(name).path
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func resolveBinaryFindsExecutableInPathEnvDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 実 PATH にも候補ディレクトリにも存在しない一意な名前で、pathEnv だけが手掛かりになるようにする。
        let name = "phlox-test-bin-\(UUID().uuidString)"
        let expected = try placeExecutable(named: name, in: dir)

        let resolved = BinaryPathResolver.resolveBinary(name, pathEnv: dir.path)

        #expect(resolved == expected)
    }

    @Test func resolveBinaryPrefersEarlierPathEnvDirectory() throws {
        let first = try makeTempDirectory()
        let second = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let name = "phlox-test-bin-\(UUID().uuidString)"
        let expected = try placeExecutable(named: name, in: first)
        _ = try placeExecutable(named: name, in: second)

        let resolved = BinaryPathResolver.resolveBinary(name, pathEnv: "\(first.path):\(second.path)")

        #expect(resolved == expected)
    }

    @Test func resolveBinarySkipsNonExecutableFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = "phlox-test-bin-\(UUID().uuidString)"
        let path = dir.appendingPathComponent(name).path
        try "not executable".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)

        #expect(BinaryPathResolver.resolveBinary(name, pathEnv: dir.path) == nil)
    }

    @Test func resolveBinaryReturnsNilWhenNotFoundAnywhere() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = BinaryPathResolver.resolveBinary(
            "phlox-test-missing-\(UUID().uuidString)",
            pathEnv: dir.path
        )

        #expect(resolved == nil)
    }
}
