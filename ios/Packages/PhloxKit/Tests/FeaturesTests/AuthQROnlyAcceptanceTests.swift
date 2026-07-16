import Testing
import PhloxCore
@testable import Features

/// task-1 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-1.md）。
///
/// 契約: 認証は QRコード読み取り一本化。QR ペイロード（host+port+token）を適用するだけで、
/// トークンの手動入力なしに接続設定が完全に確立される（configStore に host+port、
/// tokenStore に token）。手動保存経路を撤去しても QR 経路が接続確立の唯一かつ十分な手段で
/// あることを凍結する。
///
/// 出典: ios/Packages/PhloxKit/Sources/Features/Pairing/PairingApplyViewModel.swift:35-45
@Suite("task-1 QR一本化 受け入れ")
@MainActor
struct AuthQROnlyAcceptanceTests {

    private final class RecordingTokenStore: TokenStore, @unchecked Sendable {
        private(set) var stored: String?
        func save(_ token: String) async throws { stored = token }
        func load() async throws -> String? { stored }
        func delete() async throws { stored = nil }
    }

    private final class RecordingConfigStore: ConnectionConfigStoring {
        private(set) var stored: ConnectionConfig?
        func save(_ config: ConnectionConfig) { stored = config }
        func load() -> ConnectionConfig? { stored }
    }

    /// 64hex（PairingPayload 契約の token 形式）。
    private let sampleToken = String(repeating: "ab", count: 32)

    @Test("QRペイロードの適用だけで host+port+token が永続化され接続が確立する")
    func qrApplyEstablishesFullConnectionWithoutManualEntry() async {
        let tokenStore = RecordingTokenStore()
        let configStore = RecordingConfigStore()
        let vm = PairingApplyViewModel(
            tokenStore: tokenStore,
            configStore: configStore,
            probe: { _, _ in true }
        )

        await vm.apply(PairingPayload(host: "100.64.0.1", port: 8765, token: sampleToken, name: "Mac"))

        #expect(configStore.load() == ConnectionConfig(host: "100.64.0.1", port: 8765))
        #expect(tokenStore.stored == sampleToken)
        #expect(vm.phase == .success(name: "Mac"))
    }

    @Test("疎通不可でも QR による保存は巻き戻らない（QR が正）")
    func qrApplyPersistsEvenWhenUnreachable() async {
        let tokenStore = RecordingTokenStore()
        let configStore = RecordingConfigStore()
        let vm = PairingApplyViewModel(
            tokenStore: tokenStore,
            configStore: configStore,
            probe: { _, _ in false }
        )

        await vm.apply(PairingPayload(host: "100.64.0.1", port: 9000, token: sampleToken, name: nil))

        #expect(configStore.load() == ConnectionConfig(host: "100.64.0.1", port: 9000))
        #expect(tokenStore.stored == sampleToken)
    }
}
