import Foundation

public enum CodexUserHooksManagerError: Error, LocalizedError, Sendable {
    case invalidJSON(URL)
    case invalidRoot(URL)
    case invalidHooks(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let url):
            "Invalid JSON in \(url.path)"
        case .invalidRoot(let url):
            "Expected a JSON object at \(url.path)"
        case .invalidHooks(let url):
            "Expected hooks to be a JSON object in \(url.path)"
        }
    }
}

public enum CodexUserHooksStatus: Sendable, Equatable {
    case notInstalled
    case installed
    case invalid
}

/// Manages Phlox entries in the user-level Codex hooks file (`~/.codex/hooks.json`).
/// It never edits `~/.codex/config.toml` and preserves non-Phlox hook entries.
public enum CodexUserHooksManager {
    private static let events: [(name: String, kind: String)] = [
        ("Stop", "stop"),
        ("PreToolUse", "preToolUse"),
        ("PostToolUse", "postToolUse"),
        ("UserPromptSubmit", "userPromptSubmit"),
    ]

    public static var defaultCodexHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    public static func hooksFileURL(codexHome: URL = defaultCodexHome) -> URL {
        codexHome.appendingPathComponent("hooks.json", isDirectory: false)
    }

    public static func status(
        dispatcherPath: String,
        codexHome: URL = defaultCodexHome,
        fileManager: FileManager = .default
    ) -> CodexUserHooksStatus {
        let url = hooksFileURL(codexHome: codexHome)
        guard fileManager.fileExists(atPath: url.path) else { return .notInstalled }
        do {
            let root = try loadRoot(from: url)
            return containsAllPhloxHooks(root, dispatcherPath: dispatcherPath) ? .installed : .notInstalled
        } catch {
            return .invalid
        }
    }

    @discardableResult
    public static func install(
        dispatcherPath: String,
        codexHome: URL = defaultCodexHome,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let url = hooksFileURL(codexHome: codexHome)
        var root: [String: Any]
        if fileManager.fileExists(atPath: url.path) {
            root = try loadRoot(from: url)
        } else {
            root = [:]
        }

        var hooks = try hooksDictionary(from: root, sourceURL: url)
        for event in events {
            hooks[event.name] = upsertPhloxHook(
                in: hooks[event.name],
                command: command(dispatcherPath: dispatcherPath, kind: event.kind)
            )
        }
        root["hooks"] = hooks
        try write(root, to: url)
        return url
    }

    @discardableResult
    public static func remove(
        dispatcherPath: String,
        codexHome: URL = defaultCodexHome,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let url = hooksFileURL(codexHome: codexHome)
        guard fileManager.fileExists(atPath: url.path) else { return false }

        var root = try loadRoot(from: url)
        var hooks = try hooksDictionary(from: root, sourceURL: url)
        var changed = false

        for event in events {
            let command = command(dispatcherPath: dispatcherPath, kind: event.kind)
            let result = removePhloxHook(from: hooks[event.name], command: command)
            hooks[event.name] = result.value
            changed = changed || result.changed
        }

        guard changed else { return false }
        root["hooks"] = hooks
        try write(root, to: url)
        return true
    }

    public static func command(dispatcherPath: String, kind: String) -> String {
        CodexHooksManager.hookCommand(dispatcherPath: dispatcherPath, kind: kind)
    }

    private static func loadRoot(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CodexUserHooksManagerError.invalidJSON(url)
        }
        guard let root = json as? [String: Any] else {
            throw CodexUserHooksManagerError.invalidRoot(url)
        }
        return root
    }

    private static func hooksDictionary(from root: [String: Any], sourceURL: URL) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw CodexUserHooksManagerError.invalidHooks(sourceURL)
        }
        return hooks
    }

    private static func containsAllPhloxHooks(_ root: [String: Any], dispatcherPath: String) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            containsCommand(
                hooks[event.name],
                command: command(dispatcherPath: dispatcherPath, kind: event.kind)
            )
        }
    }

    private static func containsCommand(_ eventValue: Any?, command: String) -> Bool {
        guard let groups = eventValue as? [[String: Any]] else { return false }
        return groups.contains { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
            return handlers.contains { handler in
                handler["type"] as? String == "command" && handler["command"] as? String == command
            }
        }
    }

    private static func upsertPhloxHook(in eventValue: Any?, command: String) -> [[String: Any]] {
        let cleaned = removePhloxHook(from: eventValue, command: command).value
        var groups = cleaned as? [[String: Any]] ?? []
        groups.append([
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": command,
            ]],
        ])
        return groups
    }

    private static func removePhloxHook(from eventValue: Any?, command: String) -> (value: Any?, changed: Bool) {
        guard let groups = eventValue as? [[String: Any]] else {
            return (eventValue, false)
        }

        var changed = false
        let nextGroups: [[String: Any]] = groups.compactMap { group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
            let filtered = handlers.filter { handler in
                let isPhlox = handler["type"] as? String == "command"
                    && handler["command"] as? String == command
                if isPhlox { changed = true }
                return !isPhlox
            }
            guard !filtered.isEmpty else { return nil }
            var nextGroup = group
            nextGroup["hooks"] = filtered
            return nextGroup
        }

        return (nextGroups.isEmpty ? nil : nextGroups, changed)
    }

    private static func write(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
