import AgentDomain
import Foundation
import MobileProxy
import os

/// 設定画面のペアリング済み端末一覧・QR ペアリングを司る ViewModel。
///
/// 永続化・発行・失効・register のロジックは `MobileDeviceProvisioner`（AgentDomain）に委譲し、
/// ここは UI 状態とユーザー操作（QR 発行・端末失効）だけを持つ。
/// トークン文字列そのものは表示・コピーせず、QR 画像の生成にのみ使う。
@MainActor
public final class MobileTokenViewModel: ObservableObject {
  /// ペアリング済み・発行済みの端末一覧。行の表示規則（名前・ペアリング日時）はここが唯一の正本。
  @Published public private(set) var devices: [PairedDevice] = []

  /// 直近の発行・失効失敗を表すユーザー向けメッセージ。成功時・初期状態は nil。
  @Published public private(set) var lastError: String?

  /// QR ペアリング表示中か。明示操作で開始し、60 秒後に自動非表示。
  @Published public private(set) var isPairingQRVisible = false

  /// 直近に解決した露出範囲。回復・再解決で更新される。
  @Published public private(set) var bindMode: BindMode?

  /// 直近に解決したモバイルプロキシの待ち受けポート。回復・再解決で更新される。
  @Published public private(set) var mobileProxyPort: Int?

  private let provisioner: MobileDeviceProvisioner
  private let tokenStore: SessionTokenStore
  private let proxy: MobileProxy
  /// 端末集合の変化（QR 発行・失効）のたびに、最新の特権 requester 集合を Dashboard へ
  /// 反映するためのフック。集合の算出規則自体は `MobileBootstrap.privilegedRequesters(for:)`
  /// （AgentDomain 側）が正本で、ここでは再実装しない（task-4 レビュー2巡目 HIGH）。
  private let onPrivilegedRequestersChanged: (Set<SessionID>) -> Void
  /// 直近に「QR を表示」で発行した端末のトークン。QR 画像の生成にのみ使う（表示・コピーはしない）。
  private var pendingQRToken: String?
  private var hidePairingQRTask: Task<Void, Never>?
  private var autoRecoveryTask: Task<Void, Never>?

  private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "MobileToken")

  /// QR 表示の自動非表示までの秒数。
  private static let pairingQRVisibleDuration: TimeInterval = 60

  public init(
    devices: [PairedDevice],
    provisioner: MobileDeviceProvisioner,
    tokenStore: SessionTokenStore,
    proxy: MobileProxy,
    bindMode: BindMode?,
    mobileProxyPort: Int?,
    onPrivilegedRequestersChanged: @escaping (Set<SessionID>) -> Void
  ) {
    self.devices = devices
    self.provisioner = provisioner
    self.tokenStore = tokenStore
    self.proxy = proxy
    self.bindMode = bindMode
    self.mobileProxyPort = mobileProxyPort
    self.onPrivilegedRequestersChanged = onPrivilegedRequestersChanged
  }

  /// オンデマンドで Tailscale 到達性を再解決し、UI 向け状態へ反映する。
  public func refreshReachability() async {
    let refreshedBindMode = await proxy.refresh()
    let refreshedPort = await proxy.boundPort.map(Int.init)
    bindMode = refreshedBindMode
    mobileProxyPort = refreshedPort
  }

  /// 起動直後の短い自動回復を一度だけ駆動する。既に Tailscale 到達済みなら何もしない。
  public func startAutoRecovery() {
    if case .tailscale = bindMode { return }
    guard autoRecoveryTask == nil else { return }

    autoRecoveryTask = Task { [weak self] in
      guard let self else { return }
      let recoveredBindMode = await proxy.recoverUntilReachable(
        maxAttempts: 5,
        delay: .seconds(2)
      )
      let recoveredPort = await proxy.boundPort.map(Int.init)
      bindMode = recoveredBindMode
      mobileProxyPort = recoveredPort
      autoRecoveryTask = nil
    }
  }

  /// Tailscale 経由の QR ペアリングが利用可能か。
  public var isPairingQREnabled: Bool {
    pairingQRDisabledReason == nil
  }

  /// QR ボタン無効時に表示する理由。利用可能なら nil。
  public var pairingQRDisabledReason: String? {
    guard let bindMode else {
      return "モバイル接続プロキシが起動していないため、QR コードを表示できません。"
    }
    guard mobileProxyPort != nil else {
      return "モバイル接続ポートが不明なため、QR コードを表示できません。"
    }
    switch bindMode {
    case .loopbackOnly:
      return "Tailscale が検出されていません。iPhone から接続するには Tailscale で同一ネットワークに参加している必要があります。"
    case .explicitHost:
      return "現在の接続構成では QR ペアリングを利用できません。"
    case .tailscale:
      return nil
    }
  }

  /// 直近に発行した端末のトークンから `PairingPayload` を生成する（キャッシュしない）。
  public func makePairingPayload() -> Result<PairingPayload, PairingPayloadError> {
    guard let bindMode, let port = mobileProxyPort, let pendingQRToken else {
      return .failure(.unsupportedBindMode)
    }
    return PairingPayload.make(
      bindMode: bindMode,
      port: port,
      token: pendingQRToken,
      name: Host.current().localizedName
    )
  }

  /// 新しい端末を発行し QR 表示を開始する。既存端末の token / requester には触れない。
  /// 60 秒後に自動非表示。
  public func showPairingQR(deviceName: String) async {
    guard isPairingQREnabled else { return }
    do {
      let device = try provisioner.issueDevice(name: deviceName)
      await provisioner.syncRegistrations(into: tokenStore)
      try reloadDevicesAndPrivilegedRequesters()
      pendingQRToken = device.token.value
      lastError = nil
      isPairingQRVisible = true
      schedulePairingQRAutoHide()
    } catch {
      lastError = String(localized: "端末の発行に失敗しました。しばらくしてから再度お試しください。")
      Self.logger.error("Mobile device issue failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// QR ペアリング表示を手動で終了する。
  public func hidePairingQR() {
    hidePairingQRTask?.cancel()
    hidePairingQRTask = nil
    isPairingQRVisible = false
  }

  /// 端末を 1 台失効させる。失効後は `SessionTokenStore` への登録も取り消し、一覧を更新する。
  public func revoke(id: UUID) async {
    do {
      try provisioner.revoke(id: id)
      await provisioner.syncRegistrations(into: tokenStore)
      try reloadDevicesAndPrivilegedRequesters()
      lastError = nil
    } catch {
      lastError = String(localized: "端末の失効に失敗しました。しばらくしてから再度お試しください。")
      Self.logger.error("Mobile device revoke failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// `CompositionRoot` が `MobileDevicePairingRelay` 経由で、認証成立によりある端末の
  /// `pairedAt` が永続化されたことを知らせてきたときに呼ぶ（task-4 レビュー3巡目 HIGH）。
  ///
  /// iPhone で QR を読んでペアリングが成立しても、この通知が無いと設定画面の一覧が
  /// 「未接続」のまま更新されなかった。呼び出し元は既に MainActor へホップ済みである前提
  /// （`CompositionRoot` 側で `Task { @MainActor in ... }` を使う契約）。
  ///
  /// 一覧の算出規則は `showPairingQR` / `revoke` と同じ `reloadDevicesAndPrivilegedRequesters()`
  /// を使い、ここで新しい規則を作らない。再読込自体が失敗しても認証済み接続は継続しているため、
  /// ユーザー向けエラー表示（`lastError`）は出さずログにのみ残す。
  public func handleAuthenticatedPairingRecorded() {
    do {
      try reloadDevicesAndPrivilegedRequesters()
    } catch {
      Self.logger.error("Mobile device list refresh after pairing failed: \(String(describing: error), privacy: .public)")
    }
  }

  deinit {
    hidePairingQRTask?.cancel()
    autoRecoveryTask?.cancel()
  }

  /// 端末一覧・特権 requester 集合を再読込する規則の唯一の実装（task-4 レビュー3巡目 HIGH）。
  /// `showPairingQR` / `revoke` / `handleAuthenticatedPairingRecorded` はすべてこれを使い、
  /// `provisioner.loadAndMigrate()` + `MobileBootstrap.privilegedRequesters(for:)` の
  /// 呼び出しをそれぞれで再実装しない。
  private func reloadDevicesAndPrivilegedRequesters() throws {
    devices = try provisioner.loadAndMigrate()
    onPrivilegedRequestersChanged(MobileBootstrap.privilegedRequesters(for: devices))
  }

  private func schedulePairingQRAutoHide() {
    hidePairingQRTask?.cancel()
    hidePairingQRTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.pairingQRVisibleDuration))
      guard !Task.isCancelled, let self else { return }
      self.isPairingQRVisible = false
      self.hidePairingQRTask = nil
    }
  }
}
