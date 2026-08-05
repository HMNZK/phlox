import Foundation

/// `MobileBootstrap.run(provisioner:tokenStore:)` の戻り値。
public struct MobileBootstrapResult: Equatable, Sendable {
    public let devices: [PairedDevice]
    public let privilegedRequesters: Set<SessionID>

    public init(devices: [PairedDevice], privilegedRequesters: Set<SessionID>) {
        self.devices = devices
        self.privilegedRequesters = privilegedRequesters
    }
}

/// 起動時のペアリング関連処理（旧項目の削除 → 期限切れ掃除 → `SessionTokenStore` への登録 →
/// 特権 requester 集合の算出）を 1 関数にまとめる。`CompositionRoot` はこれを呼ぶだけにし、
/// 手順そのものをアプリ側で再実装しない（正本はここ）。
public enum MobileBootstrap {
    /// - 旧モデルの Keychain 項目を削除し、期限切れの未使用端末を掃除する（`loadAndMigrate`）。
    /// - 現存する全端末（ペアリング済み・未ペアリングとも）のトークンを `tokenStore` へ登録し直す
    ///   （消えた端末の登録は取り消す）。
    /// - 現存する全端末の requester を「特権 requester」として返す。
    ///   未ペアリングの端末も含む: QR 発行直後にトークンが有効化されている必要があるため。
    public static func run(
        provisioner: MobileDeviceProvisioner,
        tokenStore: SessionTokenStore
    ) async throws -> MobileBootstrapResult {
        let devices = try provisioner.loadAndMigrate()
        await provisioner.syncRegistrations(into: tokenStore)
        return MobileBootstrapResult(devices: devices, privilegedRequesters: privilegedRequesters(for: devices))
    }

    /// 端末一覧から特権 requester 集合を算出する規則の正本（task-4 レビュー2巡目 HIGH）。
    ///
    /// `run` はこれを起動時に呼ぶ。起動後に QR 発行・失効で端末集合が変わったときも、
    /// 呼び出し側（`MobileTokenViewModel`）は集合の算出規則をここへ委ね、
    /// `Set(devices.map(\.requesterSessionID))` を UI 層で再実装しない。
    /// 未ペアリングの端末も含む: QR 発行直後にトークンが有効化されている必要があるため。
    public static func privilegedRequesters(for devices: [PairedDevice]) -> Set<SessionID> {
        Set(devices.map(\.requesterSessionID))
    }

    /// `ControlServer` が Bearer トークンを認証成立させたとき（task-4）に呼ぶ。該当端末があれば
    /// `pairedAt` を記録する。永続化失敗（Keychain の読み書き失敗等）を握りつぶさず `.failure` で
    /// 呼び出し側へ返す。呼び出し側（`CompositionRoot`）はこれをログへ記録すること
    /// （トークン値は載せない・処理は続行する。認証そのものは既に成立しているため）。
    public static func recordAuthenticatedPairing(
        token: String,
        provisioner: MobileDeviceProvisioner
    ) -> Result<Void, Error> {
        do {
            try provisioner.markPaired(token: token)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// `ControlServer.onAuthenticatedToken` へ渡すフックを組み立てる。
    ///
    /// 「記録する → 成功なら UI へ通知する / 失敗ならログへ回す」という配線そのものを
    /// ここに置くことで、`CompositionRoot`（App ターゲット＝テストランナーが無い）に
    /// 検証できないロジックが残らないようにする。通知の `Task` を捨てるような改変は
    /// この関数の白箱テストで捕まる（task-4 レビュー4巡目 MEDIUM）。
    ///
    /// `onRecordFailure` にはトークン値を渡さない（不変条件）。認証自体は成立済みなので、
    /// 失敗しても例外を投げず処理を続行する。
    public static func makeAuthenticatedTokenHook(
        provisioner: MobileDeviceProvisioner,
        relay: MobileDevicePairingRelay,
        onRecordFailure: @escaping @Sendable (Error) -> Void
    ) -> @Sendable (String) -> Void {
        { token in
            switch recordAuthenticatedPairing(token: token, provisioner: provisioner) {
            case .failure(let error):
                onRecordFailure(error)
            case .success:
                Task { await relay.notify() }
            }
        }
    }
}

/// `ControlServer`（別スレッド由来）の認証成立通知を、まだ存在しない UI 層
/// （`MobileTokenViewModel`）へ後から橋渡しするためのリレー（task-4 レビュー3巡目 HIGH）。
///
/// `CompositionRoot` は `ControlServer` を先に組み立てる都合上（`MobileTokenViewModel` は
/// `ControlServer.start()` が返す `controlPort` 経由の `MobileProxy` に依存するため）、
/// `onAuthenticatedToken` クロージャを作る時点ではまだ `MobileTokenViewModel` が存在しない。
/// このリレーを先に生成してクロージャに捕捉させ、`MobileTokenViewModel` 生成後に
/// `setHandler` でハンドラを差し込む。
///
/// ハンドラの実行文脈（MainActor へ渡すかどうか）はここでは決めない。
/// `ControlServer` からの通知は別スレッド由来であり、`MobileTokenViewModel` は
/// `@MainActor` 隔離のため、ハンドラを差し込む側（`CompositionRoot`）が
/// `Task { @MainActor in ... }` で明示的にホップする契約とする。
public actor MobileDevicePairingRelay {
    private var handler: (@Sendable () -> Void)?
    /// ハンドラが差し込まれる前に届いた通知があったか。
    /// `ControlServer` はハンドラの配線より前に待受を始めるので、起動直後に
    /// ペアリングが成立するとここに通知が先着する。取りこぼすと一覧が
    /// 「未接続」のまま残るため、ラッチして `setHandler` 時に1回だけ配送する
    /// （回数は意味を持たない＝ハンドラは「最新状態を読み直す」だけなので、
    /// 溜めた分を数える必要はなく、真偽のラッチで足りる）。
    private var pendingNotification = false

    public init() {}

    /// ハンドラを差し込む。既存のハンドラは上書きする。
    /// 差し込み前に届いていた通知があれば、その場で1回配送する。
    public func setHandler(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        if pendingNotification {
            pendingNotification = false
            handler()
        }
    }

    /// 認証成立を通知する。ハンドラ未設定（＝まだ UI 層の組み立て中）なら、
    /// 取りこぼさずにラッチして `setHandler` の時点で配送する。
    public func notify() {
        guard let handler else {
            pendingNotification = true
            return
        }
        handler()
    }
}
