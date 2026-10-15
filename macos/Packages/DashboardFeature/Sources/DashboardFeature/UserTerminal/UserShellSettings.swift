import AgentDomain
import Darwin
import Foundation

public struct UserShellResolution: Equatable, Sendable {
    public let path: String
    public let unavailablePath: String?
    public let fallbackPath: String?

    public init(path: String, unavailablePath: String? = nil, fallbackPath: String? = nil) {
        self.path = path
        self.unavailablePath = unavailablePath
        self.fallbackPath = fallbackPath
    }
}

public enum UserShellSettings {
    public static let pathKey = "terminal.shellPath"

    public static func loginShellPath() -> String {
        guard let shell = getpwuid(getuid())?.pointee.pw_shell else { return "/bin/zsh" }
        let path = String(cString: shell)
        return path.isEmpty ? "/bin/zsh" : path
    }

    public static func isExecutableFile(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        var directory: ObjCBool = false
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    public static func availableShells(at url: URL = URL(fileURLWithPath: "/etc/shells")) throws -> [String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        var paths: [String] = []
        for line in contents.components(separatedBy: .newlines) {
            let path = line.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if isExecutableFile(path), !paths.contains(path) { paths.append(path) }
        }
        return paths
    }

    public static func resolve(defaults: UserDefaults = .phloxDefaults()) -> UserShellResolution {
        resolve(configuredPath: defaults.string(forKey: pathKey) ?? "", systemPath: loginShellPath())
    }

    public static func resolve(configuredPath: String, systemPath: String) -> UserShellResolution {
        let fallback = systemPath.isEmpty ? "/bin/zsh" : systemPath
        guard !configuredPath.isEmpty else { return UserShellResolution(path: fallback) }
        guard isExecutableFile(configuredPath) else {
            return UserShellResolution(path: fallback, unavailablePath: configuredPath)
        }
        return UserShellResolution(path: configuredPath, fallbackPath: fallback)
    }

    @discardableResult
    public static func save(_ path: String, defaults: UserDefaults = .phloxDefaults()) -> Bool {
        guard path.isEmpty || isExecutableFile(path) else { return false }
        defaults.set(path, forKey: pathKey)
        return true
    }
}
