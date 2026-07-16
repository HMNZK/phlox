import Foundation
import AgentDomain

@MainActor
final class NonHookIdleFallbackTracker {
    private let settleDuration: Duration

    private var inputSubmittedAt: Date?
    private var hasOutputSinceSubmit = false
    private var generation = 0
    private var task: Task<Void, Never>?

    init(settleDuration: Duration) {
        self.settleDuration = settleDuration
    }

    func markInputSubmitted() {
        inputSubmittedAt = Date()
        hasOutputSinceSubmit = false
        generation += 1
        task?.cancel()
        task = nil
    }

    func observeOutputIfNeeded(
        at outputAt: Date,
        status: SessionStatus,
        shouldSettle: @escaping @MainActor () -> Bool,
        onSettled: @escaping @MainActor () -> Void
    ) {
        guard status == .running,
              let submittedAt = inputSubmittedAt,
              outputAt >= submittedAt else { return }
        hasOutputSinceSubmit = true
        schedule(shouldSettle: shouldSettle, onSettled: onSettled)
    }

    func cancel() {
        inputSubmittedAt = nil
        hasOutputSinceSubmit = false
        generation += 1
        task?.cancel()
        task = nil
    }

    private func schedule(
        shouldSettle: @escaping @MainActor () -> Bool,
        onSettled: @escaping @MainActor () -> Void
    ) {
        generation += 1
        let currentGeneration = generation
        let delay = settleDuration
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  !Task.isCancelled,
                  currentGeneration == self.generation,
                  self.hasOutputSinceSubmit,
                  shouldSettle() else { return }
            self.inputSubmittedAt = nil
            self.hasOutputSinceSubmit = false
            onSettled()
        }
    }
}
