import Foundation
import Testing

@testable import AgentDomain

// ペアリングの一生（QR 発行 → 認証成立 → 失効）と起動シーケンス（MobileBootstrap）を、アプリが実行するのと同じ順序で固定する。
// CompositionRoot が手順を再実装せず MobileBootstrap を呼ぶだけにするための契約でもある。

private func makeProvisioner(
    store: any PairedDeviceStore,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 10_000) }
) -> MobileDeviceProvisioner {
    MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: now)
}

@Test func bootstrap_onFirstLaunch_returnsNoDevicesAndNoPrivilege() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let tokenStore = SessionTokenStore()

    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(result.devices.isEmpty)
    #expect(result.privilegedRequesters.isEmpty)
}

@Test func bootstrap_registersEveryDevice_andExposesTheirRequestersAsPrivileged() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let phone = try provisioner.issueDevice(name: "iPhone")
    let pad = try provisioner.issueDevice(name: "iPad")
    try provisioner.markPaired(token: phone.token.value)
    try provisioner.markPaired(token: pad.token.value)
    let tokenStore = SessionTokenStore()

    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(Set(result.devices.map(\.id)) == Set([phone.id, pad.id]))
    #expect(result.privilegedRequesters == Set([phone.requesterSessionID, pad.requesterSessionID]))
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)
    #expect(await tokenStore.session(forToken: pad.token.value) == pad.requesterSessionID)
}

@Test func bootstrap_isIdempotentAcrossRestarts() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = makeProvisioner(store: store, now: { Date(timeIntervalSince1970: 10_000) })
    let phone = try provisioner.issueDevice(name: "iPhone")
    try provisioner.markPaired(token: phone.token.value)

    let first = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())
    let second = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())

    #expect(first == second)
}

// 一生: QR 発行 → 認証成立 → 別端末を追加 → 1 台失効 → 残りは繋がったまま。
@Test func fullLifecycle_issueThenPairThenRevoke_keepsOtherDeviceConnected() async throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = makeProvisioner(store: store, now: { clock.now })
    let tokenStore = SessionTokenStore()

    // 1 台目: QR 発行 → スキャンして初回認証（ControlServer が解決した直後に markPaired が呼ばれる想定）。
    let phone = try provisioner.issueDevice(name: "iPhone")
    await provisioner.syncRegistrations(into: tokenStore)
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)
    try provisioner.markPaired(token: phone.token.value)

    // 2 台目を追加しても 1 台目は切れない。
    clock.advance(60)
    let pad = try provisioner.issueDevice(name: "iPad")
    await provisioner.syncRegistrations(into: tokenStore)
    try provisioner.markPaired(token: pad.token.value)
    #expect(await tokenStore.session(forToken: phone.token.value) == phone.requesterSessionID)

    // 1 台目を失効させる。
    try provisioner.revoke(id: phone.id)
    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: tokenStore)

    #expect(await tokenStore.session(forToken: phone.token.value) == nil)
    #expect(await tokenStore.session(forToken: pad.token.value) == pad.requesterSessionID)
    #expect(result.privilegedRequesters == Set([pad.requesterSessionID]))
}

// 起動時に、使われないまま期限切れになったトークンは掃除される（Q2 の決定）。
@Test func bootstrap_prunesExpiredPendingTokens() async throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = makeProvisioner(store: store, now: { clock.now })
    let stale = try provisioner.issueDevice(name: "スキャンされなかった QR")

    clock.advance(601)
    let result = try await MobileBootstrap.run(provisioner: provisioner, tokenStore: SessionTokenStore())

    #expect(result.devices.isEmpty)
    #expect(try store.loadAll().contains { $0.id == stale.id } == false)
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

// `MobileBootstrap.recordAuthenticatedPairing`: 認証成立時の永続化失敗を握りつぶすと、
// ペアリング日時が記録されず設定画面が「未接続」のまま残る。

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

// 特権 requester 集合の算出規則は `MobileBootstrap.privilegedRequesters(for:)` に一本化されている。
// 起動時だけの算出では、起動後に QR 発行した端末に特権が付かず、失効した端末の特権も残る。

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

// 認証成立の通知経路（ControlServer → CompositionRoot → MobileDevicePairingRelay → MobileTokenViewModel）。
// これが無いと、ペアリングが成立し pairedAt が保存されても設定画面の一覧は「未接続」のまま更新されない。
// `MobileDevicePairingRelay` は ControlServer 由来の別スレッドから UI 層へ後から通知を橋渡しする。

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
// 。
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

// 認証成立の記録（recordAuthenticatedPairing）→ リレー通知 → ハンドラが
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
// 捨てる改変はここで捕まる。
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
