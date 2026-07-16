import Foundation
import AgentDomain
import PTYKit
import TerminalUI

@MainActor
final class SessionDebugCapture {
    private static let rawCaptureLimit = 32 * 1024

    @MainActor
    final class RawOutputCapture {
        private var capturedBytes = 0
        private var handle: FileHandle?

        init?(url: URL) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            if handle == nil {
                return nil
            }
        }

        func write(_ data: Data) {
            guard let handle, capturedBytes < SessionDebugCapture.rawCaptureLimit else { return }
            let remaining = SessionDebugCapture.rawCaptureLimit - capturedBytes
            let chunk = data.prefix(remaining)
            try? handle.write(contentsOf: chunk)
            capturedBytes += chunk.count
            if capturedBytes >= SessionDebugCapture.rawCaptureLimit {
                close()
            }
        }

        func close() {
            try? handle?.close()
            handle = nil
        }
    }

    static func openRawOutputCapture(sessionLabel: String) -> RawOutputCapture? {
        RawOutputCapture(url: makeRawCaptureURL(sessionLabel: sessionLabel))
    }

    static func dumpAndScheduleWinsizes(
        sessionID: SessionID,
        sessionLabel: String,
        ptyManager: any PTYManagerProtocol,
        terminalCoordinator: TerminalCoordinator,
        isSessionAlive: @escaping @MainActor () -> Bool
    ) async {
        let spawnedPty = await ptyManager.getWinsize(sessionID)
            .map { (cols: Int($0.cols), rows: Int($0.rows)) }
        terminalCoordinator.dumpForDebug(
            sessionLabel: sessionLabel,
            label: "Spawned",
            ptyWinsize: spawnedPty
        )
        scheduleWinsizeDump(
            after: .milliseconds(1000),
            label: "T0",
            sessionID: sessionID,
            sessionLabel: sessionLabel,
            ptyManager: ptyManager,
            terminalCoordinator: terminalCoordinator,
            isSessionAlive: isSessionAlive
        )
        scheduleWinsizeDump(
            after: .milliseconds(2000),
            label: "T1",
            sessionID: sessionID,
            sessionLabel: sessionLabel,
            ptyManager: ptyManager,
            terminalCoordinator: terminalCoordinator,
            isSessionAlive: isSessionAlive
        )
        scheduleWinsizeDump(
            after: .milliseconds(5000),
            label: "T2",
            sessionID: sessionID,
            sessionLabel: sessionLabel,
            ptyManager: ptyManager,
            terminalCoordinator: terminalCoordinator,
            isSessionAlive: isSessionAlive
        )
    }

    private static func scheduleWinsizeDump(
        after delay: Duration,
        label: String,
        sessionID: SessionID,
        sessionLabel: String,
        ptyManager: any PTYManagerProtocol,
        terminalCoordinator: TerminalCoordinator,
        isSessionAlive: @escaping @MainActor () -> Bool
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, isSessionAlive() else { return }
            let winsize = await ptyManager.getWinsize(sessionID)
                .map { (cols: Int($0.cols), rows: Int($0.rows)) }
            terminalCoordinator.dumpForDebug(
                sessionLabel: sessionLabel,
                label: label,
                ptyWinsize: winsize
            )
        }
    }

    private static func makeRawCaptureURL(sessionLabel: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Phlox", isDirectory: true)
            .appendingPathComponent("cursor-raw-\(sessionLabel).bin")
    }
}
