import Darwin
import Foundation
import Security

@MainActor
public final class SessionRuntimeLauncher {
    private let runtimeBundleURL: URL
    private let storeURL: URL
    private let readinessTimeout: Duration
    private let spawnOverride: (@MainActor () throws -> pid_t)?

    private struct LaunchAttempt: Codable {
        let id: UUID
        let pid: pid_t?
    }

    private var attemptURL: URL { storeURL.appendingPathComponent("session-runtime/launch-attempt.json") }

    public init(runtimeBundleURL: URL, storeURL: URL) {
        self.runtimeBundleURL = runtimeBundleURL
        self.storeURL = storeURL.standardizedFileURL.resolvingSymlinksInPath()
        self.readinessTimeout = .seconds(15)
        self.spawnOverride = nil
    }

    init(runtimeBundleURL: URL, storeURL: URL, readinessTimeout: Duration, spawn: @escaping @MainActor () throws -> pid_t) {
        self.runtimeBundleURL = runtimeBundleURL
        self.storeURL = storeURL.standardizedFileURL.resolvingSymlinksInPath()
        self.readinessTimeout = readinessTimeout
        self.spawnOverride = spawn
    }

    public func connect() async throws -> SessionRuntimeEndpoint {
        let owned = try hostIsOwned()
        let launchLock = try acquireLaunchLock()
        defer { close(launchLock) }
        let existing = try SessionRuntimeLease.readDiscovery(storeURL: storeURL)
        let shouldSpawn = try !owned && !hostIsOwned() && !priorLaunchIsUnresolved()
        if shouldSpawn {
            let attempt = LaunchAttempt(id: UUID(), pid: nil)
            try writeAttempt(attempt)
            let pid: pid_t
            do {
                pid = try spawnOverride?() ?? spawn()
            } catch {
                if unlink(attemptURL.path) != 0, errno != ENOENT {
                    throw SessionRuntimeConnectionError.runtimeUnavailable("起動失敗後の記録を削除できません。\(error.localizedDescription)")
                }
                throw error
            }
            try writeAttempt(LaunchAttempt(id: attempt.id, pid: pid))
        }
        let deadline = ContinuousClock.now + readinessTimeout
        var lastFailure = "起動情報を確認できません。"
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let discovery = try SessionRuntimeLease.readDiscovery(storeURL: storeURL),
               !shouldSpawn || discovery.generation != existing?.generation {
                guard discovery.protocolVersion == SessionRuntimeEndpoint.protocolVersion else {
                    throw SessionRuntimeConnectionError.incompatibleProtocol
                }
                switch discovery.state {
                case .failed:
                    throw SessionRuntimeConnectionError.runtimeUnavailable(discovery.failure ?? "起動に失敗しました。")
                case .stopping:
                    throw SessionRuntimeConnectionError.runtimeUnavailable("終了処理中です。")
                case .starting:
                    lastFailure = "起動準備中です。"
                case .ready:
                    guard let url = discovery.desktopURL else {
                        throw SessionRuntimeConnectionError.incompatibleProtocol
                    }
                    let token = try SessionRuntimeCredentialStore.load(storeURL: storeURL)
                    let endpoint = try SessionRuntimeEndpoint(url: url, generation: discovery.generation, token: token)
                    do {
                        try await SessionRuntimeClient(endpoint: endpoint).handshake()
                        return endpoint
                    } catch let error as SessionRuntimeConnectionError {
                        throw error
                    } catch {
                        lastFailure = error.localizedDescription
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SessionRuntimeConnectionError.runtimeUnavailable(lastFailure + "既存プロセスの停止や再起動は行っていません。")
    }

    private func hostIsOwned() throws -> Bool {
        do {
            let lease = try SessionRuntimeLease(storeURL: storeURL)
            withExtendedLifetime(lease) {}
            return false
        } catch SessionRuntimeBootstrapError.alreadyOwned {
            return true
        }
    }

    private func acquireLaunchLock() throws -> Int32 {
        let path = storeURL.appendingPathComponent("session-runtime/launch.lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1 else {
            close(descriptor)
            throw SessionRuntimeConnectionError.unauthorized
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw SessionRuntimeConnectionError.runtimeUnavailable("別の画面が実行サービスへ接続中です。") }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return descriptor
    }

    private func priorLaunchIsUnresolved() throws -> Bool {
        let descriptor = open(attemptURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT { return false }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1, info.st_size <= 4096 else {
            throw SessionRuntimeConnectionError.unauthorized
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let attempt = try JSONDecoder().decode(LaunchAttempt.self, from: handle.readToEnd() ?? Data())
        guard let pid = attempt.pid, pid > 0 else {
            throw SessionRuntimeConnectionError.runtimeUnavailable("前回の起動結果が不明です。重複起動を防ぐため停止しました。")
        }
        if kill(pid, 0) == 0 { return true }
        guard errno == ESRCH else { return true }
        return false
    }

    private func writeAttempt(_ attempt: LaunchAttempt) throws {
        let temporary = attemptURL.deletingLastPathComponent().appendingPathComponent(".launch-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer {
            close(descriptor)
            if unlink(temporary.path) != 0, errno != ENOENT {
                FileHandle.standardError.write(Data("Runtime launch temporary cleanup failed (\(errno))\n".utf8))
            }
        }
        let bytes = try JSONEncoder().encode(attempt)
        try bytes.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = write(descriptor, address.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, attemptURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func spawn() throws -> pid_t {
        guard let bundle = Bundle(url: runtimeBundleURL), let executable = bundle.executableURL,
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw SessionRuntimeConnectionError.runtimeUnavailable("実行サービスのアプリが一致しません。")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(runtimeBundleURL as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw SessionRuntimeConnectionError.runtimeUnavailable("実行サービスの署名を確認できません。")
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var result = posix_spawn_file_actions_init(&actions)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        result = posix_spawnattr_init(&attributes)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        defer { posix_spawnattr_destroy(&attributes) }
        result = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            result = posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0)
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PHLOX_DATA_DIR"] = storeURL.path
        for key in ["PHLOX_TOKEN", "PHLOX_CONTROL_TOKEN", "PHLOX_SESSION_ID", "PHLOX_CONTROL_URL", "PHLOX_HOOK_PORT"] {
            environment.removeValue(forKey: key)
        }
        let arguments = [executable.path, "--session-runtime"]
        let variables = environment.map { "\($0.key)=\($0.value)" }
        let argumentPointers = arguments.map { strdup($0) }
        let variablePointers = variables.map { strdup($0) }
        defer {
            for pointer in argumentPointers + variablePointers { free(pointer) }
        }
        guard argumentPointers.allSatisfy({ $0 != nil }), variablePointers.allSatisfy({ $0 != nil }) else {
            throw POSIXError(.ENOMEM)
        }
        var argv = argumentPointers + [nil]
        var envp = variablePointers + [nil]
        var pid: pid_t = 0
        result = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        let childPID = pid
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while waitpid(childPID, &status, 0) < 0 {
                if errno != EINTR { break }
            }
        }
        return childPID
    }
}
