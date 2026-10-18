import XCTest
import PhloxCore
@testable import Features

// QR 専用の接続設定表示と、保存済み資格情報による疎通テストを検証する。
@MainActor
final class ConnectionSettingsViewModelTests: XCTestCase {
    private actor ProbeRecorder {
        private(set) var calls: [(ConnectionConfig, String?)] = []

        func record(config: ConnectionConfig, token: String?) {
            calls.append((config, token))
        }
    }

    private func makeVM(
        tokenStore: TokenStore = InMemoryTokenStore(),
        configStore: ConnectionConfigStoring = InMemoryConnectionConfigStore(),
        probe: @escaping ConnectionSettingsViewModel.Probe = { _, _ in true }
    ) -> ConnectionSettingsViewModel {
        ConnectionSettingsViewModel(tokenStore: tokenStore, configStore: configStore, probe: probe)
    }

    func testTestConnectionUsesPersistedConfigAndToken() async throws {
        let tokenStore = InMemoryTokenStore()
        try await tokenStore.save("stored-token")
        let config = ConnectionConfig(host: "100.64.0.1", port: 8765)
        let recorder = ProbeRecorder()
        let vm = makeVM(
            tokenStore: tokenStore,
            configStore: InMemoryConnectionConfigStore(config),
            probe: { config, token in
                await recorder.record(config: config, token: token)
                return true
            }
        )

        await vm.testConnection()

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, config)
        XCTAssertEqual(calls.first?.1, "stored-token")
        guard case .success(let message) = vm.banner else {
            return XCTFail("成功時は成功バナーを表示する")
        }
        XCTAssertTrue(message.range(of: #"^GET /sessions → 200 · \d{2}:\d{2} に確認$"#, options: .regularExpression) != nil)
        XCTAssertEqual(vm.connectionStatus, "接続中")
        XCTAssertEqual(vm.lastTestWasReachable, true)
    }

    func testTestConnectionFailureShowsFailureBanner() async {
        let config = ConnectionConfig(host: "saved", port: 8765)
        let vm = makeVM(
            configStore: InMemoryConnectionConfigStore(config),
            probe: { _, _ in false }
        )

        await vm.testConnection()

        XCTAssertEqual(vm.banner, .failure(ConnectionSettingsCopy.testFailureMessage))
        XCTAssertEqual(vm.connectionStatus, "Mac に届きません")
        XCTAssertEqual(vm.lastTestWasReachable, false)
    }

    func testTestConnectionWithoutSavedConfigShowsGuidanceAndDoesNotProbe() async {
        let recorder = ProbeRecorder()
        let vm = makeVM(probe: { config, token in
            await recorder.record(config: config, token: token)
            return true
        })

        await vm.testConnection()

        let calls = await recorder.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(vm.banner, .failure(ConnectionSettingsCopy.noConnectionMessage))
    }

    func testCurrentConnectionIsReadOnlyProjectionOfStoredConfig() {
        let store = InMemoryConnectionConfigStore(ConnectionConfig(host: "saved", port: 9000))
        let vm = makeVM(configStore: store)

        XCTAssertEqual(vm.currentConnection, "saved:9000")
        XCTAssertTrue(vm.hasConnectionConfig)
        XCTAssertEqual(vm.qrButtonTitle, ConnectionSettingsCopy.reconnectButtonTitle)
    }

    func testMissingConfigOffersInitialQRConnection() {
        let vm = makeVM()

        XCTAssertEqual(vm.currentConnection, ConnectionSettingsCopy.notConnectedValue)
        XCTAssertFalse(vm.hasConnectionConfig)
        XCTAssertEqual(vm.qrButtonTitle, ConnectionSettingsCopy.connectButtonTitle)
    }
}
