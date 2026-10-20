import AgentConfigKit
import AgentDomain
import Foundation

/// 補完に使うローカルのスキル置き場。有効なプラグインだけを含める。
struct AgentSkillLocation {
    let directory: URL
    let namespace: String?
}

enum AgentSkillLocations {
    static func locations(for agent: AgentKind, home: URL, workspace: URL) -> [AgentSkillLocation] {
        let folder: String
        switch agent {
        case .claudeCode: folder = ".claude"
        case .codex: folder = ".codex"
        case .cursor: folder = ".cursor"
        }
        var result = [home, workspace].map {
            AgentSkillLocation(directory: $0.appending(path: "\(folder)/skills"), namespace: nil)
        }
        switch agent {
        case .claudeCode: result += claudePlugins(home: home, workspace: workspace)
        case .codex: result += codexPlugins(home: home)
        case .cursor: break
        }
        return result
    }

    private static func claudePlugins(home: URL, workspace: URL) -> [AgentSkillLocation] {
        let registry = home.appending(path: ".claude/plugins/installed_plugins.json")
        guard let data = try? Data(contentsOf: registry),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: [[String: Any]]]
        else { return [] }

        var enabled = enabledClaudePlugins(at: home.appending(path: ".claude/settings.json"))
        enabled.merge(enabledClaudePlugins(at: workspace.appending(path: ".claude/settings.json"))) { _, project in project }
        enabled.merge(enabledClaudePlugins(at: workspace.appending(path: ".claude/settings.local.json"))) { _, project in project }
        let workspacePath = workspace.standardizedFileURL.path
        return plugins.keys.sorted().flatMap { id -> [AgentSkillLocation] in
            guard enabled[id] != false, let name = id.split(separator: "@", maxSplits: 1).first else { return [] }
            let installations = (plugins[id] ?? []).sorted {
                ($0["scope"] as? String) == "project" && ($1["scope"] as? String) != "project"
            }
            return installations.compactMap { item in
                guard let path = item["installPath"] as? String,
                      let scope = item["scope"] as? String,
                      scope != "project" || (item["projectPath"] as? String) == workspacePath
                else { return nil }
                return AgentSkillLocation(directory: URL(fileURLWithPath: path).appending(path: "skills"), namespace: String(name))
            }
        }
    }

    private static func enabledClaudePlugins(at url: URL) -> [String: Bool] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = root["enabledPlugins"] as? [String: Bool]
        else { return [:] }
        return enabled
    }

    private static func codexPlugins(home: URL) -> [AgentSkillLocation] {
        guard let config = try? String(contentsOf: home.appending(path: ".codex/config.toml"), encoding: .utf8) else { return [] }
        let document = TOMLDocument(text: config)
        let cache = home.appending(path: ".codex/plugins/cache")
        return document.subtableKeys(under: ["plugins"]).compactMap { id in
            guard document.bool(at: ["plugins", id, "enabled"]) == true else { return nil }
            let parts = id.split(separator: "@", maxSplits: 1)
            guard parts.count == 2,
                  parts.allSatisfy({ !$0.contains("/") && !$0.contains("\\") && $0 != "." && $0 != ".." })
            else { return nil }
            let pluginRoot = cache.appending(path: String(parts[1])).appending(path: String(parts[0]))
            guard let versions = try? FileManager.default.contentsOfDirectory(
                at: pluginRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return nil }
            let ordered = versions.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            guard let current = ordered.first(where: { FileManager.default.fileExists(atPath: $0.appending(path: "skills").path) }) else { return nil }
            return AgentSkillLocation(directory: current.appending(path: "skills"), namespace: String(parts[0]))
        }
    }
}
