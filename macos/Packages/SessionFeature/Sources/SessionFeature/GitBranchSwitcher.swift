import Foundation

enum GitBranchSwitcher {
    static func localBranches(at path: String) throws -> [String] {
        let output = try runGit(
            arguments: [
                "for-each-ref",
                "refs/heads",
                "--sort=-committerdate",
                "--format=%(refname:short)",
            ],
            at: path
        )
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func checkout(branch: String, at path: String) throws {
        _ = try runGit(arguments: ["checkout", branch], at: path)
    }

    private static func runGit(arguments: [String], at path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw GitBranchSwitcherError(arguments: arguments, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitBranchSwitcherError(arguments: arguments, output: output)
        }
        return output
    }
}

struct GitBranchSwitcherError: LocalizedError {
    let arguments: [String]
    let output: String

    var errorDescription: String? {
        let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "git \(arguments.joined(separator: " ")) failed"
        }
        return message
    }
}
