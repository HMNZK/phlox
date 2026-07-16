import CPTYHelpers
import Darwin
import Foundation

public enum Posix {
    public static let defaultRows: UInt16 = 24
    public static let defaultCols: UInt16 = 80

    public static func openPTY(cols: UInt16 = defaultCols, rows: UInt16 = defaultRows) throws -> (master: Int32, slave: Int32) {
        var master: Int32 = -1
        var slave: Int32 = -1
        var win = pty_winsize(
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        let result = cpty_open(&master, &slave, &win)
        guard result == 0 else {
            throw PTYError.openPTYFailed(errno: errno)
        }
        return (master, slave)
    }

    /// posix_spawn / posix_spawn_file_actions_* / posix_spawnattr_* はエラーコードを
    /// 「戻り値」で返し、errno を設定する保証がない。グローバル errno を読まず、
    /// 戻り値をそのまま `PTYError.spawnFailed(errno:)` に詰める。
    private static func checkSpawnResult(_ result: Int32) throws {
        guard result == 0 else {
            throw PTYError.spawnFailed(errno: result)
        }
    }

    public static func spawn(
        command: String,
        args: [String],
        env: [String: String],
        masterFD: Int32,
        slaveFD: Int32,
        workingDirectory: String?
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        try checkSpawnResult(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        let dupActions: [(Int32, Int32)] = [
            (slaveFD, STDIN_FILENO),
            (slaveFD, STDOUT_FILENO),
            (slaveFD, STDERR_FILENO),
        ]
        for (source, target) in dupActions {
            try checkSpawnResult(posix_spawn_file_actions_adddup2(&fileActions, source, target))
        }
        for fd in [slaveFD, masterFD] {
            try checkSpawnResult(posix_spawn_file_actions_addclose(&fileActions, fd))
        }

        if let cwd = workingDirectory {
            // posix_spawn_file_actions_addchdir_np は macOS 10.15+ で利用可能。
            // 子プロセスを起動する前に CWD を変更する。これによって、
            // 親（.app バンドル内）の不自然な CWD が claude にスキャンされて
            // /Volumes 等の TCC ダイアログが出る問題を防ぐ。
            try checkSpawnResult(cwd.withCString { cstr in
                posix_spawn_file_actions_addchdir_np(&fileActions, cstr)
            })
        }

        var attributes: posix_spawnattr_t?
        try checkSpawnResult(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }

        // 親プロセスから継承された signal disposition と signal mask を子で必ずリセットする。
        // これをしないと、親（例: Swift Testing ランナー）が SIGTERM をブロックしている場合、
        // 子プロセスにも継承されて kill(pid, SIGTERM) が効かなくなる。
        var sigFull = sigset_t()
        sigfillset(&sigFull)
        try checkSpawnResult(posix_spawnattr_setsigdefault(&attributes, &sigFull))
        var sigEmpty = sigset_t()
        sigemptyset(&sigEmpty)
        try checkSpawnResult(posix_spawnattr_setsigmask(&attributes, &sigEmpty))

        let flags = Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        try checkSpawnResult(posix_spawnattr_setflags(&attributes, flags))

        let argvStrings = [command] + args
        let envStrings = env.map { "\($0.key)=\($0.value)" }.sorted()

        return try argvStrings.withCStringBuffer { argvCStrings in
            try envStrings.withCStringBuffer { envCStrings in
                var pid: pid_t = 0
                try checkSpawnResult(command.withCString { path in
                    posix_spawn(
                        &pid,
                        path,
                        &fileActions,
                        &attributes,
                        argvCStrings,
                        envCStrings
                    )
                })
                return pid
            }
        }
    }

    public static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            let total = rawBuffer.count
            while offset < total {
                let written = write(fd, base.advanced(by: offset), total - offset)
                if written < 0 {
                    // read 側 (makeReadSource) と対称に、シグナル割り込みは失敗扱いにせず retry する。
                    if errno == EINTR { continue }
                    throw PTYError.writeFailed(errno: errno)
                }
                if written == 0 {
                    throw PTYError.writeFailed(errno: EIO)
                }
                offset += written
            }
        }
    }

    public static func terminate(pid: pid_t) throws {
        guard kill(pid, SIGTERM) == 0 else {
            throw PTYError.killFailed(errno: errno)
        }
    }

    /// SETSID 起動の子は pgid == pid。プロセスグループへ SIGTERM を送る。
    public static func terminateGroup(pid: pid_t) {
        if killpg(pid, SIGTERM) == 0 { return }
        switch errno {
        case ESRCH:
            return
        default:
            _ = kill(pid, SIGTERM)
        }
    }

    /// プロセスグループへ SIGKILL を送る。
    public static func killGroup(pid: pid_t) {
        if killpg(pid, SIGKILL) == 0 { return }
        switch errno {
        case ESRCH:
            return
        default:
            _ = kill(pid, SIGKILL)
        }
    }

    /// プロセスがまだプロセス表に存在するか (`kill(pid, 0)`)。reap 前のゾンビも true になり得る。
    public static func isAlive(pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    public static func resize(fd: Int32, cols: UInt16, rows: UInt16) throws {
        let result = cpty_set_winsize(fd, cols, rows)
        guard result == 0 else {
            throw PTYError.resizeFailed(errno: errno)
        }
    }

    /// PTY master fd の winsize を読み取る (ioctl TIOCGWINSZ wrapper)。
    /// errno 失敗時は nil を返す (観測用なので throw しない)。
    public static func getWinsize(fd: Int32) -> (cols: UInt16, rows: UInt16)? {
        var cols: UInt16 = 0
        var rows: UInt16 = 0
        let result = cpty_get_winsize(fd, &cols, &rows)
        guard result == 0 else { return nil }
        return (cols: cols, rows: rows)
    }

    /// Interprets a `waitpid` status word (Darwin `wait.h` semantics).
    public static func exitCode(from status: Int32) -> Int32 {
        if (status & 0x7F) == 0 {
            return (status >> 8) & 0xFF
        }
        return 128 + (status & 0x7F)
    }
}

private extension Array where Element == String {
    func withCStringBuffer<R>(_ body: ([UnsafeMutablePointer<CChar>?]) throws -> R) rethrows -> R {
        var copies: [UnsafeMutablePointer<CChar>?] = []
        copies.reserveCapacity(count + 1)
        defer {
            for pointer in copies where pointer != nil {
                free(pointer)
            }
        }
        for string in self {
            copies.append(strdup(string))
        }
        copies.append(nil)
        return try body(copies)
    }
}
