import CryptoKit
import Foundation

enum SessionRuntimeBundleStore {
    enum Failure: Error {
        case executableMissing
        case invalidSignature(String)
        case invalidCacheDirectory(String)
    }

    static func prepare(bundle: Bundle = .main, storeURL: URL) throws -> URL {
        guard let executable = bundle.executableURL else { throw Failure.executableMissing }
        try verify(bundle.bundleURL)
        var digest = SHA256()
        digest.update(data: try Data(contentsOf: executable, options: .mappedIfSafe))
        let resources = bundle.bundleURL.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        digest.update(data: try Data(contentsOf: resources))
        let key = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let directory = storeURL.appendingPathComponent("session-runtime-bundles", isDirectory: true)
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        }
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard values.isDirectory == true, values.isSymbolicLink != true,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw Failure.invalidCacheDirectory(directory.path)
        }
        let destination = directory.appendingPathComponent("\(key).app", isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            try verify(destination)
            return destination
        }
        let staging = directory.appendingPathComponent(".install-\(UUID().uuidString).app", isDirectory: true)
        try manager.copyItem(at: bundle.bundleURL, to: staging)
        try verify(staging)
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            guard manager.fileExists(atPath: destination.path) else { throw error }
            try verify(destination)
            try manager.removeItem(at: staging)
        }
        return destination
    }

    private static func verify(_ url: URL) throws {
        let process = Process()
        let diagnostics = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        try process.run()
        let data = diagnostics.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.invalidSignature(String(decoding: data, as: UTF8.self))
        }
    }
}
