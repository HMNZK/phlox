import Foundation

public enum MobileDeviceProvisionerError: Error, Equatable {
    /// 生成したトークンが既存端末と衝突し、規定回数の再生成でも解消しなかった。
    /// 「1 端末 = 1 トークン」の不変条件を壊すより、発行を失敗させる。
    case tokenGenerationExhausted
}

/// 端末ごとのトークンのライフサイクル（発行・ペアリング成立の記録・失効・未使用トークンの自動失効・
/// `SessionTokenStore` への同期）を司る。
///
/// ## 順序と冪等性についての設計
///
/// 発行・ペアリング成立・失効・掃除は同じ端末集合を更新するため、
/// 「一覧を読む → 加工する → 一覧ごと書き戻す」を行うと、読んでから書くまでの間に起きた
/// 別経路の変更（失効・発行）を巻き戻してしまう（失効済みの端末が復活する、
/// ペアリング直後の端末が未使用と誤判定されて消える）。
/// そのため本クラスは:
///
/// - 各操作の直前に必ず `store.loadAll()` で最新状態を読み直す（メモリキャッシュを正本にしない）
/// - 書き込みは**触る端末だけ**を対象にする（`upsert(_:)` / `remove(id:)`。`replaceAll(_:)` は使わない）
/// - **読んでから書くまでを相互排他する**（下記）
///
/// ## 相互排他（read-modify-write の直列化）
///
/// `PairedDeviceStore` に compare-and-swap が無いため、「1 件ずつ書く」だけでは
/// 読んだ後・書く前に他操作が挟まる TOCTOU が残る（掃除が一覧を読んだ直後に
/// `markPaired` された端末を、古い判定のまま消す等）。
/// そこで `issueDevice` / `markPaired` / `revoke` / `pruneExpired` / `loadAndMigrate` は
/// **読み取りから書き込みまでを 1 つのミューテックスで直列化**する。
/// `syncRegistrations` は `await` を跨ぐため `NSLock` を保持できないので、
/// 待ち行列を持つ非同期ゲート（`SerialGate`）で直列化し、古い同期の `register` が
/// 新しい同期の `remove` を覆さないようにする。
///
/// **前提: このプロビジョナはプロセス内で単一インスタンスを共有すること**（配線は task-4 が担保する）。
/// 相互排他の単位はインスタンスなので、同じ `store` に対して複数インスタンスを作ると直列化は効かない。
///
/// 時刻は `now` から取り、`Date()` を直接呼ばない（テストから注入するため）。
///
/// `SessionTokenStore` への登録済み requester を内部に記録する（可変状態を持つ）ため
/// `@unchecked Sendable`。可変部は `NSLock` で保護し、注入口（`now` / `randomBytes`）は
/// `@Sendable` を要求して、境界を跨いで持ち込まれる状態が保護されないまま入るのを防ぐ。
public final class MobileDeviceProvisioner: @unchecked Sendable {
    /// トークン衝突時の再生成回数の上限。乱数源が正常なら 1 回目で必ず通る。
    private static let tokenGenerationAttempts = 8

    private let store: any PairedDeviceStore
    private let pendingTokenTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let randomBytes: @Sendable (Int) -> [UInt8]

    /// 同期 API の read-modify-write 全体と、下の `registeredRequesters` を守る。
    /// `await` を跨いで保持しない（跨ぐ側は `syncGate` が担当する）。
    private let stateLock = NSLock()
    /// `syncRegistrations` で `SessionTokenStore` へ登録済みの requester。
    /// 端末集合の正本ではなく「トークンストアへ何を押し込んだか」の記録であり、
    /// 失効・掃除で消えた端末の登録を取り消すために使う。
    private var registeredRequesters: Set<SessionID> = []
    /// `syncRegistrations` を先着順に直列化する非同期ゲート。
    private let syncGate = SerialGate()

    public init(
        store: any PairedDeviceStore,
        pendingTokenTTL: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init,
        randomBytes: @escaping @Sendable (Int) -> [UInt8] = MobileToken.secureRandomBytes
    ) {
        self.store = store
        self.pendingTokenTTL = pendingTokenTTL
        self.now = now
        self.randomBytes = randomBytes
    }

    /// 起動時に 1 回。旧モデルの Keychain 項目を削除し、期限切れの未使用端末を掃除して、
    /// 現在の端末一覧を返す。2 回目以降に呼んでも結果は変わらない（冪等）。
    @discardableResult
    public func loadAndMigrate() throws -> [PairedDevice] {
        stateLock.lock()
        defer { stateLock.unlock() }

        try store.purgeLegacySingleToken()
        _ = try pruneExpiredLocked()
        // 掃除の結果を反映した最新状態を返す（掃除前のスナップショットを返さない）。
        return try store.loadAll()
    }

    /// QR 表示のたびに新しい端末エントリを発行する。既存端末の token / requester には触れない。
    public func issueDevice(name: String) throws -> PairedDevice {
        // 一意性の判定（読み）と登録（書き）の間に他の発行が挟まると、
        // 同じトークンの端末が 2 台できるので、ここも直列化する。
        stateLock.lock()
        defer { stateLock.unlock() }

        let existing = try store.loadAll()
        let takenTokens = Set(existing.map(\.token.value))

        var token: MobileToken?
        for _ in 0..<Self.tokenGenerationAttempts {
            let candidate = MobileToken.generate(randomBytes: randomBytes)
            if !takenTokens.contains(candidate.value) {
                token = candidate
                break
            }
        }
        guard let token else {
            throw MobileDeviceProvisionerError.tokenGenerationExhausted
        }

        let device = PairedDevice(
            id: UUID(),
            name: name,
            token: token,
            requesterSessionID: SessionID(),
            issuedAt: now(),
            pairedAt: nil
        )
        // 新規 1 件だけを足す。一覧の書き戻しをしないので、直前に失効した端末が復活しない。
        try store.upsert(device)
        return device
    }

    /// このトークンで初めて認証が成功したときに呼ぶ。`pairedAt` を確定させる。
    ///
    /// - 該当トークンが無い場合は**何もしない**。これはエラーの握りつぶしではなく契約である:
    ///   失効済み・掃除済みのトークンで認証が来ることは正常な運用（呼び出し側は別途 401 を返す）で、
    ///   ここで例外にしても呼び出し側に取れる回復手段がない。
    /// - 既に `pairedAt` が入っている端末は上書きしない（初回接触時刻を保つ）。
    public func markPaired(token: String) throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        let devices = try store.loadAll()
        guard var device = devices.first(where: { $0.token.value == token }) else { return }
        guard device.pairedAt == nil else { return }

        device.pairedAt = now()
        // 該当端末だけを書く。読んだ一覧を書き戻さないので、
        // この間に発行・失効された他端末を巻き戻さない。
        try store.upsert(device)
    }

    /// 端末を 1 台失効させる。未知の id は何もしない。
    public func revoke(id: UUID) throws {
        // 対象 1 件の削除で済むが、進行中の掃除・発行の read-modify-write の途中に
        // 割り込まないよう、同じミューテックスの下で実行する（操作全体の順序を一意にする）。
        stateLock.lock()
        defer { stateLock.unlock() }

        try store.remove(id: id)
    }

    /// 期限切れの未使用端末（`pairedAt == nil` かつ `issuedAt + TTL < now`）を削除する。冪等。
    ///
    /// 境界（`issuedAt + TTL == now`）はまだ生存させる（`<=` ではなく `<`）。
    /// `pairedAt` が入っている端末はどれだけ古くても削除しない。
    @discardableResult
    public func pruneExpired() throws -> [UUID] {
        // 「読んだ時点では期限切れ」でも、その直後に markPaired された端末を消してはならない。
        // 判定と削除の間に他操作を挟ませない（TOCTOU の遮断）。
        stateLock.lock()
        defer { stateLock.unlock() }

        return try pruneExpiredLocked()
    }

    /// `stateLock` を保持した状態で呼ぶこと。
    private func pruneExpiredLocked() throws -> [UUID] {
        let devices = try store.loadAll()
        let currentTime = now()
        let expired = devices.filter { device in
            device.pairedAt == nil && device.issuedAt.addingTimeInterval(pendingTokenTTL) < currentTime
        }

        // 生存分の書き戻し（replaceAll）ではなく、期限切れの id を 1 件ずつ消す。
        // 読み込み後に失効・発行された端末を巻き込まないため。
        for device in expired {
            try store.remove(id: device.id)
        }
        return expired.map(\.id)
    }

    /// 現在の全端末を `SessionTokenStore` へ登録し直す。
    ///
    /// 前回の同期以降に消えた端末（失効・掃除）の requester は登録を取り消すので、
    /// そのトークンは解決不能になる（＝ 401）。他セッションの登録には触れない。
    /// 同時に呼ばれても直列に適用される。古い同期の `register` が新しい同期の `remove` を
    /// 覆さないよう、一覧の読み取りから登録の反映までを丸ごとゲートの内側で行う
    /// （＝ゲートを取れた順＝一覧を読む順＝反映する順）。
    public func syncRegistrations(into tokenStore: SessionTokenStore) async {
        await syncGate.acquire()
        await applyRegistrations(into: tokenStore)
        await syncGate.release()
    }

    private func applyRegistrations(into tokenStore: SessionTokenStore) async {
        let devices: [PairedDevice]
        do {
            devices = try snapshotDevices()
        } catch {
            // 契約上 throw できない。読み出しに失敗した状態で登録を推測で書き換えると、
            // 生きている端末を切る／失効済みを復活させることになるため、現在の登録を保って戻る。
            // 次回の同期で最新状態に追いつく。
            return
        }

        let staleRequesters = swapRegisteredRequesters(to: Set(devices.map(\.requesterSessionID)))

        // 先に消えた端末を解決不能にしてから、現存端末を登録し直す。
        for requester in staleRequesters {
            await tokenStore.remove(session: requester)
        }
        for device in devices {
            await tokenStore.register(device.token.value, for: device.requesterSessionID)
        }
    }

    /// 進行中の read-modify-write の途中（例: 掃除が複数件を消している最中）を読まないよう、
    /// 同期 API と同じミューテックスの下で一覧を取る。
    /// （`NSLock` は async 文脈から直接使えないため、同期関数に切り出している）
    private func snapshotDevices() throws -> [PairedDevice] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try store.loadAll()
    }

    /// 登録済み requester の記録を最新の集合へ差し替え、消えた requester を返す。
    private func swapRegisteredRequesters(to current: Set<SessionID>) -> Set<SessionID> {
        stateLock.lock()
        defer { stateLock.unlock() }
        let stale = registeredRequesters.subtracting(current)
        registeredRequesters = current
        return stale
    }
}

/// `await` を跨ぐ区間を先着順に直列化するゲート。
///
/// `NSLock` は `await` を跨いで保持できず、actor はサスペンド点で再入するため、
/// 「実行中は 1 本だけ・待ちは到着順」を明示的な待ち行列で表す。
private actor SerialGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            // 保持権を先頭の待ち手へそのまま渡す（isHeld は true のまま）。
            waiters.removeFirst().resume()
        }
    }
}
