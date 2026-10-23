import AgentDomain
import Darwin
import Foundation

public enum SessionRuntimeLaunchRole: Equatable, Sendable {
    case graphical
    case sessionRuntime

    public init(arguments: [String]) {
        self = arguments.dropFirst().contains("--session-runtime") ? .sessionRuntime : .graphical
    }
}

public struct SessionRuntimeDiscovery: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public enum State: String, Codable, Sendable {
        case starting
        case ready
        case stopping
        case failed
    }

    public let generation: UUID
    public let protocolVersion: Int
    public let pid: Int32
    public let storeURL: URL
    public let assetsRoot: URL
    public var state: State
    public var controlURL: URL?
    public var desktopURL: URL?
    public var failure: String?
    public var interactionFailure: String?

    public init(generation: UUID = UUID(), pid: Int32 = getpid(), storeURL: URL, assetsRoot: URL) {
        self.generation = generation
        self.protocolVersion = Self.currentProtocolVersion
        self.pid = pid
        self.storeURL = storeURL
        self.assetsRoot = assetsRoot
        self.state = .starting
    }
}

public enum SessionRuntimeBootstrapError: Error, Equatable {
    case alreadyOwned
    case unsafeFile(String)
    case systemCall(String, Int32)
    case wrongStore
}

/// この FD の寿命だけが所有権を決める。発見情報の PID や接続失敗をロックの代わりに使わない。
public final class SessionRuntimeLease {
    public let storeURL: URL
    public let directoryURL: URL
    public var discoveryURL: URL { directoryURL.appendingPathComponent("discovery.json") }
    private let descriptor: Int32

    public static func resolvedStoreURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try AppSupportLocator.appSupportDirectoryURL(environment: environment)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    public init(storeURL: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: storeURL, withIntermediateDirectories: true)
        let canonicalStore = storeURL.standardizedFileURL.resolvingSymlinksInPath()
        let directory = canonicalStore.appendingPathComponent("session-runtime", isDirectory: true)
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw SessionRuntimeBootstrapError.systemCall("mkdir", errno)
        }
        try Self.validate(directory, directory: true)
        let lockURL = directory.appendingPathComponent("host.lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw SessionRuntimeBootstrapError.systemCall("open lock", errno)
        }
        do {
            try Self.validateDescriptor(descriptor, path: lockURL.path)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let code = errno
                if code == EWOULDBLOCK { throw SessionRuntimeBootstrapError.alreadyOwned }
                throw SessionRuntimeBootstrapError.systemCall("flock", code)
            }
        } catch {
            close(descriptor)
            throw error
        }
        self.storeURL = canonicalStore
        self.directoryURL = directory
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    public func publish(_ discovery: SessionRuntimeDiscovery) throws {
        guard discovery.storeURL == storeURL else { throw SessionRuntimeBootstrapError.wrongStore }
        let bytes = try JSONEncoder().encode(discovery)
        let temporary = directoryURL.appendingPathComponent(".discovery-\(UUID().uuidString)")
        let file = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw SessionRuntimeBootstrapError.systemCall("open discovery", errno) }
        defer {
            close(file)
            if unlink(temporary.path) != 0, errno != ENOENT {
                FileHandle.standardError.write(Data("Runtime discovery temporary cleanup failed (\(errno))\n".utf8))
            }
        }
        try bytes.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, address.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw SessionRuntimeBootstrapError.systemCall("write discovery", errno) }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw SessionRuntimeBootstrapError.systemCall("fsync discovery", errno) }
        guard rename(temporary.path, discoveryURL.path) == 0 else {
            throw SessionRuntimeBootstrapError.systemCall("rename discovery", errno)
        }
    }

    public static func readDiscovery(storeURL: URL) throws -> SessionRuntimeDiscovery? {
        let canonicalStore = storeURL.standardizedFileURL.resolvingSymlinksInPath()
        let directory = canonicalStore.appendingPathComponent("session-runtime", isDirectory: true)
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw SessionRuntimeBootstrapError.systemCall("lstat runtime directory", errno)
        }
        try validate(directory, directory: true)
        let url = directory.appendingPathComponent("discovery.json")
        let file = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return nil }
            throw SessionRuntimeBootstrapError.systemCall("open discovery", errno)
        }
        defer { close(file) }
        try validateDescriptor(file, path: url.path)
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        let discovery = try JSONDecoder().decode(SessionRuntimeDiscovery.self, from: data)
        guard discovery.storeURL == canonicalStore else { throw SessionRuntimeBootstrapError.wrongStore }
        return discovery
    }

    private static func validate(_ url: URL, directory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw SessionRuntimeBootstrapError.systemCall("lstat", errno)
        }
        let expectedType = directory ? S_IFDIR : S_IFREG
        let expectedMode: mode_t = directory ? 0o700 : 0o600
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == expectedType,
              info.st_mode & 0o777 == expectedMode else {
            throw SessionRuntimeBootstrapError.unsafeFile(url.path)
        }
    }

    private static func validateDescriptor(_ descriptor: Int32, path: String) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw SessionRuntimeBootstrapError.systemCall("fstat", errno)
        }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1 else {
            throw SessionRuntimeBootstrapError.unsafeFile(path)
        }
    }
}
