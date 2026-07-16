import Foundation

/// チェックアウト中ブランチの軽量読み取り（プロセス起動なし・.git/HEAD の解析のみ）。
public enum GitBranchReader {
    /// - `ref: refs/heads/<branch>` → `<branch>`
    /// - detached HEAD（生 SHA）→ 先頭 7 文字
    /// - `.git` がファイル（worktree の `gitdir: <path>` 間接参照）→ 参照先の HEAD を同規則で解決
    /// - リポジトリでない → nil
    public static func currentBranch(at path: String) -> String? {
        guard let headContent = readHEAD(at: path) else { return nil }
        return parseBranch(from: headContent)
    }

    private static func readHEAD(at path: String) -> String? {
        let gitPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else {
            return nil
        }

        let headURL: URL
        if isDirectory.boolValue {
            headURL = URL(fileURLWithPath: gitPath, isDirectory: true).appendingPathComponent("HEAD")
        } else {
            guard let gitFile = try? String(contentsOf: URL(fileURLWithPath: gitPath), encoding: .utf8) else {
                return nil
            }
            let trimmed = gitFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("gitdir: ") else { return nil }
            let gitdirPath = String(trimmed.dropFirst("gitdir: ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headURL = URL(fileURLWithPath: gitdirPath, isDirectory: true).appendingPathComponent("HEAD")
        }

        guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBranch(from headContent: String) -> String? {
        let prefix = "ref: refs/heads/"
        if headContent.hasPrefix(prefix) {
            let branch = String(headContent.dropFirst(prefix.count))
            return branch.isEmpty ? nil : branch
        }
        let sha = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sha.count >= 7 else { return nil }
        return String(sha.prefix(7))
    }
}
