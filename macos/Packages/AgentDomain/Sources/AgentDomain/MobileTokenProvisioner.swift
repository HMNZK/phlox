import Foundation

/// 永続化されたモバイルトークンと、それに紐づく安定した requester SessionID の組。
public struct ProvisionedMobileToken: Equatable, Sendable {
    public let token: MobileToken
    /// このトークンに対応する安定した requester SessionID（永続）。
    /// MC-2b が特権 requester として参照する。
    public let requesterSessionID: SessionID

    public init(token: MobileToken, requesterSessionID: SessionID) {
        self.token = token
        self.requesterSessionID = requesterSessionID
    }
}

/// モバイル専用トークンのライフサイクル（初回生成 / ロード / 再発行 / register）を司る。
///
/// - 初回起動: 32 バイト乱数 → 64hex トークンを生成して永続化し、安定 requester SessionID も確定・永続化する。
/// - 2 回目以降: 永続化済みの値をロードする。
/// - `regenerate()`: トークンだけを更新（旧トークンを無効化）。requester SessionID は安定のまま維持する。
/// - `register(_:into:)`: `SessionTokenStore` に token → requesterSessionID をマップ登録する。
///
/// `randomBytes` を差し込むことでトークン生成を決定的にテストできる。
public final class MobileTokenProvisioner: @unchecked Sendable {
    private let store: MobileTokenStore
    private let randomBytes: (Int) -> [UInt8]

    public init(
        store: MobileTokenStore,
        randomBytes: @escaping (Int) -> [UInt8] = MobileToken.secureRandomBytes
    ) {
        self.store = store
        self.randomBytes = randomBytes
    }

    /// 永続化済みのトークン・requester があればロードし、無ければ生成して永続化する。
    /// requester SessionID は一度確定したら以後変わらない（安定）。
    @discardableResult
    public func loadOrProvision() throws -> ProvisionedMobileToken {
        let requester = try loadOrCreateRequesterSessionID()
        if let token = try store.loadToken() {
            return ProvisionedMobileToken(token: token, requesterSessionID: requester)
        }
        let token = MobileToken.generate(randomBytes: randomBytes)
        try store.saveToken(token)
        return ProvisionedMobileToken(token: token, requesterSessionID: requester)
    }

    /// 新しいトークンを生成して永続化し、旧トークンを無効化する。requester SessionID は維持する。
    /// 呼び出し側は返り値で `register(_:into:)` を再実行し、`SessionTokenStore` の旧トークンも失効させること。
    @discardableResult
    public func regenerate() throws -> ProvisionedMobileToken {
        let requester = try loadOrCreateRequesterSessionID()
        let token = MobileToken.generate(randomBytes: randomBytes)
        try store.saveToken(token)
        return ProvisionedMobileToken(token: token, requesterSessionID: requester)
    }

    /// `SessionTokenStore` に token → requesterSessionID を register する。
    ///
    /// `SessionTokenStore.register` のセマンティクス上、同一 requester への再 register は
    /// その requester に紐づく旧トークンのみを失効させ、他セッションのマップは巻き込まない。
    public func register(_ provisioned: ProvisionedMobileToken, into tokenStore: SessionTokenStore) async {
        await tokenStore.register(provisioned.token.value, for: provisioned.requesterSessionID)
    }

    private func loadOrCreateRequesterSessionID() throws -> SessionID {
        if let existing = try store.loadRequesterSessionID() {
            return existing
        }
        let created = SessionID()
        try store.saveRequesterSessionID(created)
        return created
    }
}
