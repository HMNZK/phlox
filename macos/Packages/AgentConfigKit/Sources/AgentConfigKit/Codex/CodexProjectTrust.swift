import Foundation

/// `[projects."<path>"]` 1件。Codex はここで「そのディレクトリを信頼するか」を持つ。
public struct CodexProjectTrust: Sendable, Equatable, Identifiable {
    public let path: String
    public let trustLevel: String?

    public var id: String { path }

    /// `trust_level = "trusted"` かどうか。
    public var isTrusted: Bool { trustLevel == "trusted" }

    /// 画面に出す短縮パス（`~` 表記）。
    public func displayPath(homeDirectory: URL) -> String {
        let home = homeDirectory.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public init(path: String, trustLevel: String?) {
        self.path = path
        self.trustLevel = trustLevel
    }
}

/// プロジェクト信頼設定の読み書き。
public enum CodexProjectTrustSettings {
    public static func entries(from document: TOMLDocument) -> [CodexProjectTrust] {
        document.subtableKeys(under: ["projects"]).map { path in
            CodexProjectTrust(
                path: path,
                trustLevel: document.string(at: ["projects", path, "trust_level"])
            )
        }
    }

    public static func setTrusted(_ trusted: Bool, path: String, in document: inout TOMLDocument) {
        document.setString(trusted ? "trusted" : "untrusted", at: ["projects", path, "trust_level"])
    }

    /// 登録ごと消す（Codex は次回そのディレクトリで改めて確認する）。
    public static func remove(path: String, in document: inout TOMLDocument) {
        document.removeTable(["projects", path])
    }
}
