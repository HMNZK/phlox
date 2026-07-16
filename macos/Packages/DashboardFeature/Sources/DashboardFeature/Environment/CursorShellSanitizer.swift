import AgentDomain
import Foundation

enum CursorShellSanitizer {
    private static let directoryName = "cursor-empty-zdotdir"

    static func sanitizedEnvironment(base: [String: String], zdotDir: String) -> [String: String] {
        var result = base
        result["ZDOTDIR"] = zdotDir
        return result
    }

    static func ensureEmptyZDotDir(inParent parent: URL) throws -> URL {
        let fileManager = FileManager.default
        let dir = parent.appendingPathComponent(directoryName, isDirectory: true)

        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                try fileManager.removeItem(at: dir)
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        } else {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let contents = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in contents {
            try fileManager.removeItem(at: item)
        }

        return dir
    }

    static func sanitizedLaunchEnvironment(fallback environment: [String: String]) -> [String: String] {
        do {
            let zdotDir = try ensureEmptyZDotDir(inParent: defaultZDotDirParent())
            return sanitizedEnvironment(base: environment, zdotDir: zdotDir.path)
        } catch {
            return environment
        }
    }

    private static func defaultZDotDirParent() -> URL {
        let parent = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return parent.appendingPathComponent(AppFlavor.current.appSupportDirectoryName, isDirectory: true)
    }
}
