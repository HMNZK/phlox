import CryptoKit
import Foundation

/// 更新通知だけではなく、参照するファイル一式が同じかを確認する。
enum CodexSkillFingerprint {
    static func read(skillPath: String) -> String? {
        let skill = URL(fileURLWithPath: skillPath)
        var root = skill.deletingLastPathComponent()
        var candidate = root
        var foundManifest = false
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("plugin.json").path)
                || FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".codex-plugin/plugin.json").path) {
                guard !foundManifest else { return nil }
                root = candidate
                foundManifest = true
            }
            candidate.deleteLastPathComponent()
        }
        var enumerationFailed = false
        guard FileManager.default.fileExists(atPath: skill.path),
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                errorHandler: { _, _ in enumerationFailed = true; return false }
              )
        else { return nil }
        var paths: [URL] = []
        for case let path as URL in enumerator {
            guard paths.count < 4_096 else { return nil }
            paths.append(path)
        }
        guard !enumerationFailed else { return nil }
        do {
            var hash = SHA256()
            for path in paths.sorted(by: { $0.path < $1.path }) {
                let values = try path.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { return nil }
                let name = String(path.path.dropFirst(root.path.count))
                hash.update(data: Data(name.utf8))
                hash.update(data: Data([0]))
                if values.isDirectory == true {
                    hash.update(data: Data([0]))
                } else {
                    guard values.isRegularFile == true else { return nil }
                    let handle = try FileHandle(forReadingFrom: path)
                    do {
                        let size = try handle.seekToEnd()
                        try handle.seek(toOffset: 0)
                        hash.update(data: Data([1, FileManager.default.isExecutableFile(atPath: path.path) ? 1 : 0]))
                        hash.update(data: Data(String(size).utf8))
                        hash.update(data: Data([0]))
                        var bytesRead: UInt64 = 0
                        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                            bytesRead += UInt64(chunk.count)
                            if bytesRead > size { break }
                            hash.update(data: chunk)
                        }
                        try handle.close()
                        guard bytesRead == size else { return nil }
                    } catch {
                        try handle.close()
                        throw error
                    }
                }
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
