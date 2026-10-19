import Foundation

/// ネイティブ入力中の通知を、最新の1件だけ次のMainActorターンへ渡す。
@MainActor
final class DSInputSelectionDelivery {
    private var generation = 0

    func invalidate() { generation += 1 }

    @discardableResult
    func enqueue(isCurrent: @escaping @MainActor () -> Bool, apply: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        generation += 1
        let scheduledGeneration = generation
        return Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, generation == scheduledGeneration, isCurrent() else { return }
            apply()
        }
    }
}
