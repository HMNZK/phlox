import Testing
import PhloxCore
@testable import Features

private final class SpyTokenStore: TokenStore, @unchecked Sendable {
    var saved: [String] = []
    func save(_ token: String) async throws { saved.append(token) }
    func load() async throws -> String? { saved.last }
    func delete() async throws { saved.removeAll() }
}

private final class SpyConfigStore: ConnectionConfigStoring {
    var saved: [ConnectionConfig] = []
    func save(_ config: ConnectionConfig) { saved.append(config) }
    func load() -> ConnectionConfig? { saved.last }
}

private let token = String(repeating: "cd", count: 32)

@Suite("PairingApplyViewModel 白箱")
@MainActor
struct PairingApplyViewModelTests {

    @Test("初期 phase は idle")
    func startsIdle() {
        let vm = PairingApplyViewModel(
            tokenStore: SpyTokenStore(),
            configStore: SpyConfigStore(),
            probe: { _, _ in true }
        )
        #expect(vm.phase == .idle)
    }

    @Test("apply 中は applying を経由する")
    func passesThroughApplying() async {
        let gate = ApplyingGate()
        let vm = PairingApplyViewModel(
            tokenStore: SpyTokenStore(),
            configStore: SpyConfigStore(),
            probe: { _, _ in
                await gate.enterProbeAndWait()
                return true
            }
        )

        let task = Task { await vm.apply(samplePayload(name: "Lab")) }
        await gate.waitUntilProbeEntered()
        #expect(vm.phase == .applying)
        gate.releaseProbe()
        await task.value
        #expect(vm.phase == .success(name: "Lab"))
    }

    @Test("probe 失敗時の guidance は PairingCopy と同一インスタンス相当の文字列")
    func unreachableUsesCopy() async {
        let vm = PairingApplyViewModel(
            tokenStore: SpyTokenStore(),
            configStore: SpyConfigStore(),
            probe: { _, _ in false }
        )
        await vm.apply(samplePayload(name: nil))
        #expect(vm.phase == .unreachable(guidance: PairingCopy.unreachableGuidance))
    }

    private func samplePayload(name: String?) -> PairingPayload {
        PairingPayload(host: "100.64.12.34", port: 8765, token: token, name: name)
    }
}

@MainActor
private final class ApplyingGate {
    private var probeEnteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseProbeContinuation: CheckedContinuation<Void, Never>?

    func waitUntilProbeEntered() async {
        await withCheckedContinuation { probeEnteredContinuation = $0 }
    }

    func enterProbeAndWait() async {
        probeEnteredContinuation?.resume()
        probeEnteredContinuation = nil
        await withCheckedContinuation { releaseProbeContinuation = $0 }
    }

    func releaseProbe() {
        releaseProbeContinuation?.resume()
        releaseProbeContinuation = nil
    }
}
