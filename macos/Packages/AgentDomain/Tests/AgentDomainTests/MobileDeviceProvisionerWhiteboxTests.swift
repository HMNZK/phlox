import Foundation
import Testing

@testable import AgentDomain

// task-2 の白箱テスト（実装役が敵対的に足したもの）。
// 受け入れテストは「発行 → 失効 → 掃除」を逐次呼び出しでしか検証しない。
// ここでは **読み取りと書き戻しの間に別経路の変更が入る** 状況を注入して、
// 「読んだ一覧をそのまま書き戻す（replaceAll による read-modify-write）」実装を落とす。

// MARK: - テスト用ストア

/// `loadAll()` が値を返した「直後」に、1 回だけ別経路の変更を注入するストア。
/// 呼び出し側が握っているのは変更前のスナップショットになるため、
/// スナップショットを丸ごと書き戻す実装は必ず矛盾を起こす。
private final class SnapshotRacingStore: PairedDeviceStore, @unchecked Sendable {
    private let inner = InMemoryPairedDeviceStore()
    private let lock = NSLock()
    private var pendingMutation: ((InMemoryPairedDeviceStore) throws -> Void)?
    private var loadFailure: (any Error)?
    private var purgeFailure: (any Error)?
    private var purgeCount = 0
    private var pairedIDs = Set<UUID>()
    private var removedPairedIDs = Set<UUID>()

    init() {}

    /// 次の `loadAll()` の戻り値が確定した後に 1 回だけ走る変更を仕込む。
    func mutateOnceAfterNextLoad(_ mutation: @escaping (InMemoryPairedDeviceStore) throws -> Void) {
        lock.lock()
        defer { lock.unlock() }
        pendingMutation = mutation
    }

    func failNextLoads(with error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        loadFailure = error
    }

    func failPurge(with error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        purgeFailure = error
    }

    var purgeLegacyCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return purgeCount
    }

    /// 「`pairedAt` 入りで保存された端末が、その後 `remove` された」ことを記録する。
    /// これは掃除がハザード2 を踏んだ（ペアリング済みを消した）ことの直接の証拠になる。
    var pairedDevicesRemoved: Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        return removedPairedIDs
    }

    /// テストの検証用に、注入を通さず素の中身を読む。
    func rawDevices() throws -> [PairedDevice] {
        try inner.loadAll()
    }

    func seed(_ device: PairedDevice) throws {
        try inner.upsert(device)
    }

    // MARK: PairedDeviceStore

    func loadAll() throws -> [PairedDevice] {
        lock.lock()
        let failure = loadFailure
        lock.unlock()
        if let failure { throw failure }

        let snapshot = try inner.loadAll()
        lock.lock()
        let mutation = pendingMutation
        pendingMutation = nil
        lock.unlock()
        try mutation?(inner)
        return snapshot
    }

    func upsert(_ device: PairedDevice) throws {
        lock.lock()
        if device.pairedAt == nil {
            pairedIDs.remove(device.id)
        } else {
            pairedIDs.insert(device.id)
        }
        lock.unlock()
        try inner.upsert(device)
    }

    func remove(id: UUID) throws {
        lock.lock()
        if pairedIDs.contains(id) {
            removedPairedIDs.insert(id)
        }
        lock.unlock()
        try inner.remove(id: id)
    }

    func replaceAll(_ devices: [PairedDevice]) throws {
        try inner.replaceAll(devices)
    }

    func purgeLegacySingleToken() throws {
        lock.lock()
        purgeCount += 1
        let failure = purgeFailure
        lock.unlock()
        if let failure { throw failure }
    }
}

private struct TestStoreError: Error, Equatable {
    let label: String
}

private func unpairedDevice(
    name: String,
    issuedAt: Date,
    token: String = UUID().uuidString
) -> PairedDevice {
    PairedDevice(
        id: UUID(),
        name: name,
        token: MobileToken(value: token),
        requesterSessionID: SessionID(),
        issuedAt: issuedAt,
        pairedAt: nil
    )
}

// MARK: - ハザード1: 失効・削除と掃除の競合（古いスナップショットの書き戻し）

@Test func pruneExpired_doesNotResurrectDeviceRemovedAfterItsSnapshot() throws {
    // 掃除が一覧を読んだ後に、別経路（失効）で端末が消える。
    // 生存分を replaceAll で書き戻す実装は、消えたはずの端末を復活させる。
    let store = SnapshotRacingStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { clock.now })
    let pairedButRevoked = PairedDevice(
        id: UUID(),
        name: "失効させる（ペアリング済み）",
        token: MobileToken(value: "aa"),
        requesterSessionID: SessionID(),
        issuedAt: clock.now,
        pairedAt: clock.now
    )
    let expired = unpairedDevice(name: "期限切れ", issuedAt: clock.now, token: "bb")
    try store.seed(pairedButRevoked)
    try store.seed(expired)
    clock.advance(601)
    store.mutateOnceAfterNextLoad { inner in try inner.remove(id: pairedButRevoked.id) }

    let removed = try provisioner.pruneExpired()

    #expect(removed == [expired.id])
    #expect(try store.rawDevices().isEmpty)
}

@Test func pruneExpired_doesNotEraseDeviceIssuedAfterItsSnapshot() throws {
    // 掃除が一覧を読んだ後に発行された端末を、古いスナップショットの書き戻しで消してはならない。
    let store = SnapshotRacingStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { clock.now })
    let expired = unpairedDevice(name: "期限切れ", issuedAt: clock.now, token: "cc")
    try store.seed(expired)
    clock.advance(601)
    let issuedDuringPrune = unpairedDevice(name: "掃除中に発行", issuedAt: clock.now, token: "dd")
    store.mutateOnceAfterNextLoad { inner in try inner.upsert(issuedDuringPrune) }

    let removed = try provisioner.pruneExpired()

    #expect(removed == [expired.id])
    #expect(try store.rawDevices().map(\.id) == [issuedDuringPrune.id])
}

// MARK: - ハザード2: ペアリング成立の書き込みが他端末を巻き戻す

@Test func markPaired_doesNotResurrectDeviceRemovedAfterItsSnapshot() throws {
    // markPaired が一覧を読んだ後に別端末が失効した場合、その端末を書き戻して復活させない。
    let store = SnapshotRacingStore()
    let pairedAt = Date(timeIntervalSince1970: 10_000)
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { pairedAt })
    let target = unpairedDevice(name: "ペアリングする", issuedAt: pairedAt, token: "ee")
    let revokedMeanwhile = unpairedDevice(name: "同時に失効する", issuedAt: pairedAt, token: "ff")
    try store.seed(target)
    try store.seed(revokedMeanwhile)
    store.mutateOnceAfterNextLoad { inner in try inner.remove(id: revokedMeanwhile.id) }

    try provisioner.markPaired(token: "ee")

    let remaining = try store.rawDevices()
    #expect(remaining.map(\.id) == [target.id])
    #expect(remaining.first?.pairedAt == pairedAt)
}

@Test func markPaired_doesNotEraseDeviceIssuedAfterItsSnapshot() throws {
    let store = SnapshotRacingStore()
    let pairedAt = Date(timeIntervalSince1970: 10_000)
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { pairedAt })
    let target = unpairedDevice(name: "ペアリングする", issuedAt: pairedAt, token: "gg")
    try store.seed(target)
    let issuedMeanwhile = unpairedDevice(name: "同時に発行", issuedAt: pairedAt, token: "hh")
    store.mutateOnceAfterNextLoad { inner in try inner.upsert(issuedMeanwhile) }

    try provisioner.markPaired(token: "gg")

    let remaining = try store.rawDevices()
    #expect(Set(remaining.map(\.id)) == Set([target.id, issuedMeanwhile.id]))
    #expect(remaining.first { $0.id == target.id }?.pairedAt == pairedAt)
    #expect(remaining.first { $0.id == issuedMeanwhile.id }?.pairedAt == nil)
}

@Test func issueDevice_doesNotEraseDeviceIssuedAfterItsSnapshot() throws {
    let store = SnapshotRacingStore()
    let issuedAt = Date(timeIntervalSince1970: 10_000)
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { issuedAt })
    let concurrent = unpairedDevice(name: "同時に発行", issuedAt: issuedAt, token: "ii")
    store.mutateOnceAfterNextLoad { inner in try inner.upsert(concurrent) }

    let issued = try provisioner.issueDevice(name: "本命")

    #expect(Set(try store.rawDevices().map(\.id)) == Set([concurrent.id, issued.id]))
}

// MARK: - TOCTOU（レビュー1巡目 findings 1-3）: read-modify-write の相互排他

// 割り込み用の共通ハーネス。
// `loadAll()` の直後（＝プロビジョナが一覧を読んでから書くまでの窓）で、
// **別の実行文脈からプロビジョナの公開 API を呼ぶ**。
//
// 観測するのは次の 2 つの事実で、テスト側で必ず両方をアサートする。
// 「割り込みが起きなかった」と「相互排他が効いて窓の中で待たされた」を区別するため:
//
// - `startedInsideWindow`: 割り込みが**窓が開いている間に対象 API の呼び出しへ到達した**か。
//   判定は待ち手側の時間切れではなく、**割り込み側が到達時点で窓の開閉フラグを読んで記録**する。
// - `completedInsideWindow`: 窓の中で**完走できた**か。
//   相互排他が無い実装では true（＝窓の中に他操作の書き込みが差し込まれる）、
//   ある実装ではロック待ちで false になる。
//
// 待ち時間の設計（偽 red を作らないための要点）:
// - **開始待ちに実時間の上限を置かない**。`markStarted()` までの経路はスレッド起動だけで、
//   プロビジョナのロックにもタスク実行資源にも依存しないので必ず到達する。
//   上限を置くと、負荷の高いマシンで正しい実装が偽 red になる（レビュー3巡目の指摘）。
// - **完走待ちだけ上限つき**。ここは「上限まで完走しない＝直列化された」という判定そのものなので、
//   上限が要る。相互排他がある実装ではここで待たされるのが正常。
// - ハング（＝実装のデッドロック）の保険は各テストの `.timeLimit` に委ねる。
private final class Interruption: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let completed = DispatchSemaphore(value: 0)
    /// テスト末尾で割り込みを取りこぼさないための合流用（別セマフォにしないと二重待ちになる）。
    private let joinable = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var windowIsOpen = false
    private var startedWhileWindowOpen: Bool?
    private var completionObservation: DispatchTimeoutResult?

    /// 競合窓を開く（割り込みを起こす直前に呼ぶ）。
    fileprivate func openWindow() {
        lock.lock()
        defer { lock.unlock() }
        windowIsOpen = true
    }

    /// 割り込み本体が「これから対象 API を呼ぶ」時点で呼ぶ。
    /// その瞬間に窓が開いていたかを、割り込み側の観測として記録する。
    fileprivate func markStarted() {
        lock.lock()
        startedWhileWindowOpen = windowIsOpen
        lock.unlock()
        started.signal()
    }

    fileprivate func markCompleted() {
        completed.signal()
        joinable.signal()
    }

    /// 窓の中で観測する。開始は上限なしで待ち（必ず到達する）、完走だけを上限つきで待つ。
    fileprivate func observeInsideWindow(completionWithin timeout: TimeInterval) {
        started.wait()
        let completion = completed.wait(timeout: .now() + timeout)
        lock.lock()
        completionObservation = completion
        windowIsOpen = false
        lock.unlock()
    }

    /// 割り込みが競合窓の中で開始したか（false なら、そもそも競合を再現できていない）。
    var startedInsideWindow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return startedWhileWindowOpen == true
    }

    /// 割り込みが競合窓の中で完走したか（相互排他があれば false）。
    var completedInsideWindow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completionObservation == .success
    }

    /// 割り込みの終了を待つ（相互排他がある実装では窓を出た後に完走する）。
    /// 上限は置かない — 窓を出ればロックは空くので必ず完走する。ハングの保険は `.timeLimit`。
    func join() {
        joinable.wait()
    }

    /// 「窓の中で開始し、しかし窓の中では完走しなかった」＝直列化されたことの検査。
    func expectSerializedOutsideWindow() {
        #expect(startedInsideWindow, "割り込みが競合窓の中で開始していない（競合を再現できていない）")
        #expect(completedInsideWindow == false, "割り込みが競合窓の中で完走した（相互排他が効いていない）")
    }
}

private func interruptDuringNextLoad(
    on store: SnapshotRacingStore,
    waitingUpTo timeout: TimeInterval = 0.2,
    interruption: @escaping @Sendable () -> Void
) -> Interruption {
    let handle = Interruption()
    store.mutateOnceAfterNextLoad { _ in
        handle.openWindow()
        Thread {
            handle.markStarted()
            interruption()
            handle.markCompleted()
        }.start()
        handle.observeInsideWindow(completionWithin: timeout)
    }
    return handle
}

// findings 1: 掃除が「読んだ時点では期限切れ」の端末を、その直後に markPaired されても消してしまう。
@Test(.timeLimit(.minutes(1))) func pruneExpired_doesNotRemoveDevicePairedDuringItsReadModifyWrite() throws {
    let store = SnapshotRacingStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { clock.now })
    let device = try provisioner.issueDevice(name: "掃除の途中でペアリングされる")
    clock.advance(601)

    let interruption = interruptDuringNextLoad(on: store) {
        try? provisioner.markPaired(token: device.token.value)
    }
    _ = try provisioner.pruneExpired()
    interruption.join()

    // 割り込み（markPaired）は競合窓の中で始まり、しかし窓の中では完走できなかった＝直列化された。
    interruption.expectSerializedOutsideWindow()
    // ペアリング済みとして保存された端末が掃除で消された＝ハザード2 が TOCTOU として成立している。
    #expect(store.pairedDevicesRemoved.isEmpty)
    // 直列化された結果は「掃除が先（端末は消え、後続の markPaired は該当なしで no-op）」か
    // 「ペアリングが先（端末は pairedAt 付きで残る）」のどちらか。中間状態は許されない。
    let remaining = try store.rawDevices()
    if let survivor = remaining.first {
        #expect(remaining.count == 1)
        #expect(survivor.pairedAt != nil)
    }
}

// findings 3: 発行の read-modify-write に割り込まれると、同じトークンの端末が 2 台できる。
@Test(.timeLimit(.minutes(1))) func issueDevice_concurrentIssueDuringReadModifyWrite_keepsTokensUnique() throws {
    let store = SnapshotRacingStore()
    // 最初の 2 回の乱数取得は同じ値を返す（＝素朴な実装なら同一トークンが 2 台分できる）。
    let callCount = AtomicCounter()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) },
        randomBytes: { count in
            let nth = callCount.next()
            return [UInt8](repeating: nth <= 2 ? 0x5a : UInt8(truncatingIfNeeded: nth), count: count)
        }
    )

    let interruption = interruptDuringNextLoad(on: store) {
        _ = try? provisioner.issueDevice(name: "割り込みで発行")
    }
    _ = try provisioner.issueDevice(name: "本命")
    interruption.join()

    interruption.expectSerializedOutsideWindow()
    let devices = try store.rawDevices()
    #expect(devices.count == 2)
    #expect(Set(devices.map(\.token.value)).count == 2)
    #expect(Set(devices.map(\.requesterSessionID)).count == 2)
}

// findings 2: 古い同期の register が、後から走った同期の remove を覆して失効済みトークンを復活させる。
@Test(.timeLimit(.minutes(1))) func syncRegistrations_concurrentSyncs_doNotResurrectRevokedRegistration() async throws {
    let store = SnapshotRacingStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let kept = try provisioner.issueDevice(name: "手元の iPad")
    let revoked = try provisioner.issueDevice(name: "なくした iPhone")
    let tokenStore = SessionTokenStore()
    await provisioner.syncRegistrations(into: tokenStore)

    // 同期 A が一覧を読んだ直後に、失効させたうえで同期 B を走らせる。
    let interruption = Interruption()
    let syncB = TaskBox()
    store.mutateOnceAfterNextLoad { inner in
        try inner.remove(id: revoked.id)
        interruption.openWindow()
        // Task の生成は素の Thread から行う。窓の中では協調スレッドを 1 本塞いでいるので、
        // 「開始の記録」が Task の実行資源に依存すると、資源が空くまで到達できない
        // （＝上限なし待機がハングしうる）。生成だけなら資源に依存しない。
        Thread {
            syncB.hold(Task {
                await provisioner.syncRegistrations(into: tokenStore)
                interruption.markCompleted()
            })
            interruption.markStarted()
        }.start()
        // 予算 1.0 秒: `await` 側の割り込みは Task のスケジューリング待ちが入るため、
        // 0.3 秒だとゲートを外した実装でも「窓の中で完走しなかった」と誤判定して変異を取り逃す
        // （負荷時の偽 green）。実測で 1.0 秒あれば取り逃さない。
        interruption.observeInsideWindow(completionWithin: 1.0)
    }
    await provisioner.syncRegistrations(into: tokenStore)
    await syncB.value()

    // 同期 B は競合窓の中で始まり、ゲート待ちで窓の中では完走しなかった＝直列化された。
    interruption.expectSerializedOutsideWindow()

    #expect(await tokenStore.session(forToken: revoked.token.value) == nil)
    #expect(await tokenStore.session(forToken: kept.token.value) == kept.requesterSessionID)
}

/// 同期クロージャの中で起こした `Task` を、後から `await` するために保持する箱。
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func hold(_ task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
    }

    func value() async {
        await held()?.value
    }

    private func held() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }
}

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

// MARK: - ハザード3: 境界時刻（`<` と `<=` の取り違え）

@Test func pruneExpired_withZeroTTL_keepsDeviceIssuedExactlyNow() throws {
    // TTL 0 で issuedAt == now。`<=` にすると即座に消えるので取り違えを検出できる。
    let store = InMemoryPairedDeviceStore()
    let issuedAt = Date(timeIntervalSince1970: 10_000)
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 0, now: { issuedAt })

    let device = try provisioner.issueDevice(name: "同時刻")
    let removed = try provisioner.pruneExpired()

    #expect(removed.isEmpty)
    #expect(try store.loadAll().map(\.id) == [device.id])
}

@Test func pruneExpired_withZeroTTL_removesDeviceIssuedBeforeNow() throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 0, now: { clock.now })
    let device = try provisioner.issueDevice(name: "1 ミリ秒前")

    clock.advance(0.001)
    let removed = try provisioner.pruneExpired()

    #expect(removed == [device.id])
    #expect(try store.loadAll().isEmpty)
}

@Test func pruneExpired_withFractionalTTL_keepsDeviceExactlyAtBoundary() throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 0.5, now: { clock.now })
    let device = try provisioner.issueDevice(name: "小数境界")

    clock.advance(0.5)
    let atBoundary = try provisioner.pruneExpired()
    clock.advance(0.25)
    let afterBoundary = try provisioner.pruneExpired()

    #expect(atBoundary.isEmpty)
    #expect(afterBoundary == [device.id])
}

@Test func pruneExpired_removesOnlyExpiredUnpairedDevices() throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { clock.now })
    let expired = try provisioner.issueDevice(name: "期限切れ未使用")
    let pairedOld = try provisioner.issueDevice(name: "古いがペアリング済み")
    try provisioner.markPaired(token: pairedOld.token.value)
    clock.advance(601)
    let fresh = try provisioner.issueDevice(name: "新しい未使用")

    let removed = try provisioner.pruneExpired()

    #expect(removed == [expired.id])
    #expect(Set(try store.loadAll().map(\.id)) == Set([pairedOld.id, fresh.id]))
}

// MARK: - 時刻注入（`Date()` の直接呼び出しが残っていないこと）

@Test func issueDevice_stampsIssuedAtFromInjectedClock() throws {
    let store = InMemoryPairedDeviceStore()
    let fixed = Date(timeIntervalSince1970: 1_234_567)
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { fixed })

    let device = try provisioner.issueDevice(name: "iPhone")

    #expect(device.issuedAt == fixed)
    #expect(try store.loadAll().first?.issuedAt == fixed)
}

// MARK: - 1:1 対応（同じ token を持つ端末を作らない）

@Test func issueDevice_whenRandomBytesCollide_throwsAndKeepsSingleDevice() throws {
    // 乱数源が同じ値を返し続けたら、同一トークンの端末を 2 台作らずに失敗する（1:1 対応の不変条件）。
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) },
        randomBytes: { count in [UInt8](repeating: 0x7f, count: count) }
    )
    let first = try provisioner.issueDevice(name: "1 台目")

    #expect(throws: MobileDeviceProvisionerError.tokenGenerationExhausted) {
        _ = try provisioner.issueDevice(name: "2 台目")
    }
    #expect(try store.loadAll().map(\.id) == [first.id])
}

@Test func issueDevice_concurrentCalls_produceDistinctTokensAndSessions() throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )

    DispatchQueue.concurrentPerform(iterations: 32) { index in
        _ = try? provisioner.issueDevice(name: "端末 \(index)")
    }

    let devices = try store.loadAll()
    #expect(devices.count == 32)
    #expect(Set(devices.map(\.token.value)).count == 32)
    #expect(Set(devices.map(\.requesterSessionID)).count == 32)
}

// MARK: - loadAndMigrate（旧項目の削除とエラーの伝播）

@Test func loadAndMigrate_purgesLegacyItemsEveryTime() throws {
    let store = SnapshotRacingStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )

    _ = try provisioner.loadAndMigrate()
    _ = try provisioner.loadAndMigrate()

    #expect(store.purgeLegacyCallCount == 2)
}

@Test func loadAndMigrate_propagatesPurgeFailure() throws {
    // 旧項目の削除に失敗したら黙って握りつぶさず throw する（`try?` 化の検出）。
    let store = SnapshotRacingStore()
    store.failPurge(with: TestStoreError(label: "purge"))
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )

    #expect(throws: TestStoreError(label: "purge")) {
        _ = try provisioner.loadAndMigrate()
    }
}

@Test func pruneExpired_propagatesLoadFailure() throws {
    let store = SnapshotRacingStore()
    store.failNextLoads(with: TestStoreError(label: "load"))
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )

    #expect(throws: TestStoreError(label: "load")) {
        _ = try provisioner.pruneExpired()
    }
}

// MARK: - SessionTokenStore への同期

@Test func syncRegistrations_afterPrune_makesPrunedTokenUnresolvable() async throws {
    let store = InMemoryPairedDeviceStore()
    let clock = TestClock(Date(timeIntervalSince1970: 10_000))
    let provisioner = MobileDeviceProvisioner(store: store, pendingTokenTTL: 600, now: { clock.now })
    let expiring = try provisioner.issueDevice(name: "使われない")
    let kept = try provisioner.issueDevice(name: "使う")
    try provisioner.markPaired(token: kept.token.value)
    let tokenStore = SessionTokenStore()
    await provisioner.syncRegistrations(into: tokenStore)

    clock.advance(601)
    _ = try provisioner.pruneExpired()
    await provisioner.syncRegistrations(into: tokenStore)

    #expect(await tokenStore.session(forToken: expiring.token.value) == nil)
    #expect(await tokenStore.session(forToken: kept.token.value) == kept.requesterSessionID)
}

@Test func syncRegistrations_doesNotDisturbUnrelatedSessions() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let device = try provisioner.issueDevice(name: "iPhone")
    let tokenStore = SessionTokenStore()
    let foreignSession = SessionID()
    await tokenStore.register("foreign-session-token", for: foreignSession)

    await provisioner.syncRegistrations(into: tokenStore)
    try provisioner.revoke(id: device.id)
    await provisioner.syncRegistrations(into: tokenStore)

    #expect(await tokenStore.session(forToken: "foreign-session-token") == foreignSession)
    #expect(await tokenStore.token(for: foreignSession) == "foreign-session-token")
    #expect(await tokenStore.session(forToken: device.token.value) == nil)
}

@Test func syncRegistrations_repeatedCalls_keepAllDevicesResolvable() async throws {
    let store = InMemoryPairedDeviceStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let first = try provisioner.issueDevice(name: "iPhone")
    let second = try provisioner.issueDevice(name: "iPad")
    let tokenStore = SessionTokenStore()

    await provisioner.syncRegistrations(into: tokenStore)
    await provisioner.syncRegistrations(into: tokenStore)
    await provisioner.syncRegistrations(into: tokenStore)

    #expect(await tokenStore.session(forToken: first.token.value) == first.requesterSessionID)
    #expect(await tokenStore.session(forToken: second.token.value) == second.requesterSessionID)
}

@Test func syncRegistrations_whenStoreReadFails_keepsExistingRegistrations() async throws {
    // 契約上 throw できない。読めなかったときに登録を推測で書き換えると生きている端末を切るので、
    // 直前の登録を保ったまま何もしない（この振る舞いを明示的に固定する）。
    let store = SnapshotRacingStore()
    let provisioner = MobileDeviceProvisioner(
        store: store,
        pendingTokenTTL: 600,
        now: { Date(timeIntervalSince1970: 10_000) }
    )
    let device = try provisioner.issueDevice(name: "iPhone")
    let tokenStore = SessionTokenStore()
    await provisioner.syncRegistrations(into: tokenStore)

    store.failNextLoads(with: TestStoreError(label: "load"))
    await provisioner.syncRegistrations(into: tokenStore)

    #expect(await tokenStore.session(forToken: device.token.value) == device.requesterSessionID)
}
