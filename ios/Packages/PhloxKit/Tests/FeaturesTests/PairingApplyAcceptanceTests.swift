import Testing
import Foundation
import PhloxCore
@testable import Features

// task-1 受け入れテスト（PM 著・凍結）。契約: tasks/task-1.md
// PairingApplyViewModel: 保存（config/token）→ 疎通プローブ → phase 遷移。probe 失敗でも保存を保持する。

private final class SpyTokenStore: TokenStore, @unchecked Sendable {
    var saved: [String] = []
    var shouldThrowOnSave = false
    struct SaveError: Error {}
    func save(_ token: String) async throws {
        if shouldThrowOnSave { throw SaveError() }
        saved.append(token)
    }
    func load() async throws -> String? { saved.last }
    func delete() async throws { saved.removeAll() }
}

private final class SpyConfigStore: ConnectionConfigStoring {
    var saved: [ConnectionConfig] = []
    func save(_ config: ConnectionConfig) { saved.append(config) }
    func load() -> ConnectionConfig? { saved.last }
}

private let token = String(repeating: "ab", count: 32) // 64桁 hex

@Suite("PairingApplyViewModel 受け入れ")
@MainActor
struct PairingApplyAcceptanceTests {

    @Test("apply は config と token を保存し、probe 成功で .success(name:) になる")
    func appliesAndSucceeds() async {
        let tokenStore = SpyTokenStore()
        let configStore = SpyConfigStore()
        let vm = PairingApplyViewModel(tokenStore: tokenStore, configStore: configStore, probe: { _, _ in true })
        await vm.apply(PairingPayload(host: "100.64.12.34", port: 8765, token: token, name: "Studio"))

        #expect(configStore.saved == [ConnectionConfig(host: "100.64.12.34", port: 8765)])
        #expect(tokenStore.saved == [token])
        #expect(vm.phase == .success(name: "Studio"))
    }

    @Test("name 無しの成功は .success(name: nil)")
    func succeedsWithoutName() async {
        let vm = PairingApplyViewModel(tokenStore: SpyTokenStore(), configStore: SpyConfigStore(), probe: { _, _ in true })
        await vm.apply(PairingPayload(host: "100.64.12.34", port: 8765, token: token, name: nil))
        #expect(vm.phase == .success(name: nil))
    }

    @Test("probe 失敗でも保存は保持され、再スキャン案内の .unreachable になる")
    func keepsSavedDataWhenUnreachable() async {
        let tokenStore = SpyTokenStore()
        let configStore = SpyConfigStore()
        let vm = PairingApplyViewModel(tokenStore: tokenStore, configStore: configStore, probe: { _, _ in false })
        await vm.apply(PairingPayload(host: "100.64.99.99", port: 1234, token: token, name: nil))

        #expect(configStore.saved == [ConnectionConfig(host: "100.64.99.99", port: 1234)])
        #expect(tokenStore.saved == [token])
        #expect(vm.phase == .unreachable(guidance: PairingCopy.unreachableGuidance))
        #expect(PairingCopy.unreachableGuidance.contains("再表示"))
        #expect(PairingCopy.unreachableGuidance.contains("スキャン"))
    }

    @Test("probe には保存したのと同じ config と token が渡る")
    func probeReceivesAppliedValues() async {
        let received = Box<(ConnectionConfig, String?)?>(nil)
        let vm = PairingApplyViewModel(
            tokenStore: SpyTokenStore(),
            configStore: SpyConfigStore(),
            probe: { config, token in received.value = (config, token); return true }
        )
        await vm.apply(PairingPayload(host: "100.1.2.3", port: 4567, token: token, name: nil))
        #expect(received.value?.0 == ConnectionConfig(host: "100.1.2.3", port: 4567))
        #expect(received.value?.1 == token)
    }

    @Test("tokenStore.save が throw してもクラッシュせず処理が完了する")
    func survivesTokenSaveFailure() async {
        let tokenStore = SpyTokenStore()
        tokenStore.shouldThrowOnSave = true
        let configStore = SpyConfigStore()
        let vm = PairingApplyViewModel(tokenStore: tokenStore, configStore: configStore, probe: { _, _ in true })
        await vm.apply(PairingPayload(host: "100.64.12.34", port: 8765, token: token, name: nil))
        #expect(configStore.saved.count == 1)
        #expect(vm.phase != .applying) // 終端状態に到達している（applying のまま止まらない）
    }
}

/// probe closure（@Sendable）から書き戻すための箱。テスト専用。
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
