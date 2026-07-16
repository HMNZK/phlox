import Foundation
import AgentDomain

@MainActor
final class SubmitDiagnosticRecorder {
    var timeout: Duration = .seconds(3)
    var sink: @MainActor (String) -> Void = SubmitDiagnosticRecorder.appendSubmitDiagnostic

    private let sessionLabel: String
    private let agentKind: @MainActor () -> AgentKind
    private let visibleText: @MainActor () -> String

    private var armedAt: Date?
    private var byteCount = 0
    private var bracketed = false
    private var observedProcessing = false
    private var generation = 0
    private var task: Task<Void, Never>?

    init(
        sessionLabel: String,
        agentKind: @escaping @MainActor () -> AgentKind,
        visibleText: @escaping @MainActor () -> String
    ) {
        self.sessionLabel = sessionLabel
        self.agentKind = agentKind
        self.visibleText = visibleText
    }

    var isArmed: Bool {
        armedAt != nil
    }

    /// 処理中を観測済みか。`arm()` で再武装されるまで false へ戻らない（単調）ため、
    /// テストはこれが true になるのを待てば以後 flush が診断を発火しないことを確定できる。
    var hasObservedProcessing: Bool {
        observedProcessing
    }

    func arm(byteCount: Int, bracketed: Bool) {
        armedAt = Date()
        self.byteCount = byteCount
        self.bracketed = bracketed
        observedProcessing = false
        generation += 1
        let currentGeneration = generation
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.timeout)
            guard !Task.isCancelled, currentGeneration == self.generation else { return }
            self.flush()
        }
    }

    func observeProcessingIfVisible(in visibleText: String) {
        guard isArmed, CodexSessionAdapter.indicatesProcessing(in: visibleText) else { return }
        observedProcessing = true
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        armedAt = nil
    }

    private func flush() {
        defer {
            armedAt = nil
            task = nil
        }
        guard !observedProcessing else { return }
        let diagnostic = SubmitDiagnostic(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sessionLabel: sessionLabel,
            kind: agentKind(),
            byteCount: byteCount,
            bracketed: bracketed,
            timeoutSeconds: Double(timeout.components.seconds),
            visibleTail: String(visibleText().suffix(300))
        )
        sink(diagnostic.logLine)
    }

    private static func appendSubmitDiagnostic(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Phlox", isDirectory: true)
            .appendingPathComponent("send-diagnostics.log")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
