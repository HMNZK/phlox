import Foundation
import Testing

@testable import AgentDomain

// task-4 の白箱テスト。凍結された受け入れテスト
// （AcceptancePairingLifecycleIntegrationTests.swift）ではカバーされない
// `MobileBootstrap.run` の内部分岐（未ペアリング端末の扱い・エラー伝播）を検証する。

private func makeProvisioner(
    store: any PairedDeviceStore,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 10_000) }
) -> MobileDeviceProvisioner {
    MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: now)
}

// issueDevice 直後（まだ markPaired されていない）の端末も、QR 読み取りでの初回認証を
// 通すためトークンが有効でなければならない。bootstrap はそれを特権集合にも含める。
@Test func run_includesUnpairedIssuedDevice_inPrivilegedRequestersAndTokenStore() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let tokenStore = SessionTokenStore()
    let phone = try provisioner.issueDevice(name: "iPhone")
    // markPaired は呼ばない: QR 発行直後・未スキャンの状態を模す。

    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(result.devices.map(\.id) == [phone.id])
    #expect(result.privilegedRequesters == Set([phone.requesterSessionID]))
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)
}

// store.loadAll() が失敗する状況（Keychain デコード失敗等）では、bootstrap は
// 握りつぶさずエラーを伝播する（CompositionRoot 側でフォールバック判断できるように）。
@Test func run_propagatesProvisionerLoadFailure() async throws {
    let store = ThrowingPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let tokenStore = SessionTokenStore()

    await #expect(throws: PairedDeviceStoreError.self) {
        _ = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)
    }
}

// task-4 レビュー指摘（独立レビュー1巡目 HIGH）: CompositionRoot 側の `onAuthenticatedToken`
// フックが `try? mobileProvisioner.markPaired(token:)` で永続化失敗を握りつぶしていた
// （＝ペアリング日時が記録されず設定画面が「未接続」のまま残る）。ログ記録を挟めるよう
// `MobileBootstrap.recordAuthenticatedPairing` へ切り出し、ここで白箱テストする。

// 該当端末があり永続化も成功する通常経路: pairedAt が記録される。
@Test func recordAuthenticatedPairing_onSuccess_marksDevicePaired() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let phone = try provisioner.issueDevice(name: "iPhone")

    try MobileBootstrap.recordAuthenticatedPairing(token: phone.token.value, provisioner: provisioner).get()

    let reloaded = try store.loadAll().first { $0.id == phone.id }
    #expect(reloaded?.pairedAt != nil)
}

// store の書き込み失敗（Keychain 障害等）を握りつぶさず `.failure` で返す
// （呼び出し側の CompositionRoot がこれをログへ記録し、認証済みの接続は切らずに続行する契約）。
@Test func recordAuthenticatedPairing_onStoreFailure_returnsFailureWithoutThrowing() {
    let store = ThrowingPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)

    let result = MobileBootstrap.recordAuthenticatedPairing(token: "valid-token", provisioner: provisioner)

    switch result {
    case .success:
        Issue.record("expected .failure but got .success")
    case .failure(let error):
        #expect(error is PairedDeviceStoreError)
    }
}

// task-4 レビュー指摘（独立レビュー2巡目 HIGH）: 起動時の `MobileBootstrap.run` だけでは、
// 起動後に QR 発行した端末に特権が付かず、失効した端末の特権も残ったままになっていた
// （`MobileTokenViewModel` が集合を再計算せず、Dashboard へも伝えていなかったため）。
// 算出規則を `MobileBootstrap.privilegedRequesters(for:)` へ一本化し、ここで固定する。

// 起動後（＝ MobileBootstrap.run 済み）に QR で追加発行した端末も、
// 同じ算出規則を通せば特権 requester 集合に入る。
@Test func privilegedRequesters_includesDeviceIssuedAfterStartup() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let tokenStore = SessionTokenStore()
    let phone = try provisioner.issueDevice(name: "iPhone")
    let bootstrapResult = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    let pad = try provisioner.issueDevice(name: "iPad")
    let currentDevices = try provisioner.loadAndMigrate()
    let updatedRequesters = MobileBootstrap.privilegedRequesters(for: currentDevices)

    #expect(updatedRequesters.isSuperset(of: bootstrapResult.privilegedRequesters))
    #expect(updatedRequesters.contains(pad.requesterSessionID))
    #expect(updatedRequesters.contains(phone.requesterSessionID))
}

// 失効させた端末の requester は、再計算後の集合から外れる。
@Test func privilegedRequesters_excludesRevokedDevice() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let phone = try provisioner.issueDevice(name: "iPhone")
    let pad = try provisioner.issueDevice(name: "iPad")

    try provisioner.revoke(id: phone.id)
    let remainingDevices = try provisioner.loadAndMigrate()
    let requesters = MobileBootstrap.privilegedRequesters(for: remainingDevices)

    #expect(!requesters.contains(phone.requesterSessionID))
    #expect(requesters.contains(pad.requesterSessionID))
}

// 起動時（run）と、発行を重ねた後の再計算（privilegedRequesters(for:)）が同じ規則で
// 算出されること（規則の二重実装を防ぐための一致確認）。
@Test func privilegedRequesters_matchesRuleUsedByBootstrapRun() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let tokenStore = SessionTokenStore()
    _ = try provisioner.issueDevice(name: "iPhone")
    _ = try provisioner.issueDevice(name: "iPad")

    let bootstrapResult = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)
    let recomputed = MobileBootstrap.privilegedRequesters(for: bootstrapResult.devices)

    #expect(recomputed == bootstrapResult.privilegedRequesters)
}

// task-4 レビュー指摘（独立レビュー3巡目 HIGH）: 認証成立の通知経路
// （ControlServer → CompositionRoot → MobileDevicePairingRelay → MobileTokenViewModel）が
// 無かったため、iPhone で QR を読んでペアリングが成立し pairedAt が保存されても、
// 設定画面の一覧は「未接続」のまま更新されなかった。ControlServer 由来の別スレッドから、
// まだ存在しない UI 層（MobileTokenViewModel）へ後から通知を橋渡しする
// `MobileDevicePairingRelay` を検証する。

// ハンドラを先に差し込んでおけば notify() で確実に呼ばれる。
@Test func mobileDevicePairingRelay_notify_invokesHandlerSetBeforehand() async {
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()
    await relay.setHandler { calls.increment() }

    await relay.notify()

    #expect(calls.count == 1)
}

// ハンドラ未設定時に届いた通知はラッチされ、setHandler の時点で1回だけ配送される。
// ControlServer はハンドラの配線より前に待受を始めるので、起動直後にペアリングが
// 成立するとここに通知が先着する。取りこぼすと一覧が「未接続」のまま残る
// （task-4 レビュー4巡目 HIGH）。
@Test func mobileDevicePairingRelay_notifyBeforeHandlerSet_isDeliveredOnSetHandler() async {
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()

    await relay.notify() // ハンドラ未設定。ラッチされる。
    #expect(calls.count == 0)

    await relay.setHandler { calls.increment() }

    #expect(calls.count == 1)
}

// ラッチは1回だけ。setHandler を2回呼んでも、先着していた通知が二重配送されない。
@Test func mobileDevicePairingRelay_latchedNotification_isDeliveredOnlyOnce() async {
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()

    await relay.notify()
    await relay.setHandler { calls.increment() }
    await relay.setHandler { calls.increment() }

    #expect(calls.count == 1)
}

// 先着した通知が複数あっても、ハンドラは「最新状態を読み直す」だけなので1回配送で足りる。
@Test func mobileDevicePairingRelay_multipleNotificationsBeforeHandler_collapseToOneDelivery() async {
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()

    await relay.notify()
    await relay.notify()
    await relay.notify()
    await relay.setHandler { calls.increment() }

    #expect(calls.count == 1)
}

// task-4 の本筋: 認証成立の記録（recordAuthenticatedPairing）→ リレー通知 → ハンドラが
// 端末一覧を再読込、という一連の流れで pairedAt が反映されることを固定する。
// CompositionRoot 側の実際のハンドラは MobileTokenViewModel.handleAuthenticatedPairingRecorded()
// だが、App ターゲットにはテストランナーが無いため、同じ「通知 → 再読込」の配線を
// ここ（AgentDomain）で再現して固定する。
@Test func mobileDevicePairingRelay_afterRecordAuthenticatedPairing_handlerObservesPairedAt() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let phone = try provisioner.issueDevice(name: "iPhone")
    let relay = MobileDevicePairingRelay()
    let reloadedDevices = DeviceListBox()
    await relay.setHandler {
        reloadedDevices.set(try? provisioner.loadAndMigrate())
    }

    // 通知前は一覧を一度も読み込んでいない（初期状態を模す）。
    #expect(reloadedDevices.get() == nil)

    try MobileBootstrap.recordAuthenticatedPairing(token: phone.token.value, provisioner: provisioner).get()
    await relay.notify()

    let devices = try #require(reloadedDevices.get())
    let pairedDevice = try #require(devices.first { $0.id == phone.id })
    #expect(pairedDevice.pairedAt != nil)
}

// CompositionRoot が ControlServer へ渡すフックそのものを検証する。
// 「記録 → 成功なら通知」の配線を AgentDomain 側へ切り出してあるので、通知の Task を
// 捨てる改変はここで捕まる（task-4 レビュー4巡目 MEDIUM）。
@Test func authenticatedTokenHook_onSuccess_recordsPairedAtAndNotifiesRelay() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store)
    let phone = try provisioner.issueDevice(name: "iPhone")
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()
    let failures = CallCounter()
    await relay.setHandler { calls.increment() }

    let hook = MobileBootstrap.makeAuthenticatedTokenHook(
        provisioner: provisioner,
        relay: relay,
        onRecordFailure: { _ in failures.increment() }
    )
    hook(phone.token.value)

    // 通知は Task 経由なので、届くまで待つ（固定 sleep ではなくポーリング）。
    let notified = await waitUntilTrue { calls.count == 1 }
    #expect(notified)
    #expect(failures.count == 0)

    let paired = try #require(try store.loadAll().first { $0.id == phone.id })
    #expect(paired.pairedAt != nil)
}

// 記録に失敗したら、通知せずに失敗だけを呼び出し側へ回す（一覧を空振りで再読込しない）。
@Test func authenticatedTokenHook_onStoreFailure_reportsFailureAndDoesNotNotify() async throws {
    let provisioner = MobileDeviceProvisioner(
        store: ThrowingPairedDeviceStore(),
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let relay = MobileDevicePairingRelay()
    let calls = CallCounter()
    let failures = CallCounter()
    await relay.setHandler { calls.increment() }

    let hook = MobileBootstrap.makeAuthenticatedTokenHook(
        provisioner: provisioner,
        relay: relay,
        onRecordFailure: { _ in failures.increment() }
    )
    hook("any-token")

    let reported = await waitUntilTrue { failures.count == 1 }
    #expect(reported)
    #expect(calls.count == 0)
}

/// 条件が満たされるまで短い間隔でポーリングする（実時間 sleep への依存を避ける）。
private func waitUntilTrue(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ condition: @Sendable () -> Bool
) async -> Bool {
    var waited: UInt64 = 0
    let step: UInt64 = 1_000_000
    while waited < timeoutNanoseconds {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: step)
        waited += step
    }
    return condition()
}

/// `loadAll` / `purgeLegacySingleToken` が常に失敗するテスト専用フェイク。
private final class ThrowingPairedDeviceStore: PairedDeviceStore, @unchecked Sendable {
    func loadAll() throws -> [PairedDevice] {
        throw PairedDeviceStoreError.decodingFailed
    }

    func upsert(_ device: PairedDevice) throws {
        throw PairedDeviceStoreError.decodingFailed
    }

    func remove(id: UUID) throws {
        throw PairedDeviceStoreError.decodingFailed
    }

    func replaceAll(_ devices: [PairedDevice]) throws {
        throw PairedDeviceStoreError.decodingFailed
    }

    func purgeLegacySingleToken() throws {}
}

/// `MobileDevicePairingRelay` のハンドラ呼び出し回数を数えるテスト専用フェイク。
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }
}

/// ハンドラ内で読み込んだ端末一覧を保持するテスト専用フェイク。
private final class DeviceListBox: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [PairedDevice]?

    func set(_ devices: [PairedDevice]?) {
        lock.lock()
        self.devices = devices
        lock.unlock()
    }

    func get() -> [PairedDevice]? {
        lock.lock()
        defer { lock.unlock() }
        return devices
    }
}
