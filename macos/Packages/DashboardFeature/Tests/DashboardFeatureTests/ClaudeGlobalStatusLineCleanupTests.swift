import Foundation
import Testing
@testable import DashboardFeature

@Suite struct ClaudeGlobalStatusLineCleanupTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// statusLine が今も Phlox 管理値のまま → 元へ復元し、ラッパー/manifest を削除（他キーは保持）。
    @Test func managed_restoresOriginalAndDeletesArtifacts() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settingsURL = dir.appendingPathComponent("settings.json")
        let wrapperURL = dir.appendingPathComponent("wrapper.sh")
        let manifestURL = dir.appendingPathComponent("manifest.json")

        let managed = "/bin/sh '\(wrapperURL.path)'"
        let settings = "{\"permissions\":{\"x\":1},\"statusLine\":{\"type\":\"command\",\"command\":\"\(managed)\"}}"
        try Data(settings.utf8).write(to: settingsURL)
        try Data("#!/bin/sh\n".utf8).write(to: wrapperURL)
        let manifest = "{\"managedStatusLineCommand\":\"\(managed)\",\"originalStatusLine\":{\"type\":\"command\",\"command\":\"python3 ~/.claude/statusline.py\"}}"
        try Data(manifest.utf8).write(to: manifestURL)

        ClaudeGlobalStatusLineCleanup.cleanupLeftoverInstall(
            settingsURL: settingsURL, wrapperURL: wrapperURL, manifestURL: manifestURL
        )

        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        let sl = restored["statusLine"] as! [String: Any]
        #expect(sl["command"] as? String == "python3 ~/.claude/statusline.py")
        #expect(restored["permissions"] as? [String: Any] != nil)
        #expect(!FileManager.default.fileExists(atPath: wrapperURL.path))
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
    }

    /// ユーザーが statusLine を変更済み → settings.json は触らず、Phlox 資産だけ削除。
    @Test func userModified_doesNotTouchSettings_butDeletesArtifacts() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settingsURL = dir.appendingPathComponent("settings.json")
        let wrapperURL = dir.appendingPathComponent("wrapper.sh")
        let manifestURL = dir.appendingPathComponent("manifest.json")

        let managed = "/bin/sh '\(wrapperURL.path)'"
        try Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"my-own-statusline\"}}".utf8).write(to: settingsURL)
        try Data("#!/bin/sh\n".utf8).write(to: wrapperURL)
        try Data("{\"managedStatusLineCommand\":\"\(managed)\",\"originalStatusLine\":null}".utf8).write(to: manifestURL)

        ClaudeGlobalStatusLineCleanup.cleanupLeftoverInstall(
            settingsURL: settingsURL, wrapperURL: wrapperURL, manifestURL: manifestURL
        )

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        let sl = after["statusLine"] as! [String: Any]
        #expect(sl["command"] as? String == "my-own-statusline")
        #expect(!FileManager.default.fileExists(atPath: wrapperURL.path))
        #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
    }

    /// manifest 無し（設置されていない）→ settings.json は不変（no-op）。
    @Test func noManifest_isNoOp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settingsURL = dir.appendingPathComponent("settings.json")
        let wrapperURL = dir.appendingPathComponent("wrapper.sh")
        let manifestURL = dir.appendingPathComponent("manifest.json")

        try Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"x\"}}".utf8).write(to: settingsURL)

        ClaudeGlobalStatusLineCleanup.cleanupLeftoverInstall(
            settingsURL: settingsURL, wrapperURL: wrapperURL, manifestURL: manifestURL
        )

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        let sl = after["statusLine"] as! [String: Any]
        #expect(sl["command"] as? String == "x")
    }
}
