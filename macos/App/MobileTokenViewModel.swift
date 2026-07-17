import AgentDomain
import Foundation
import MobileProxy
import os

/// 設定画面のモバイルトークン再発行・QR ペアリングを司る ViewModel。
///
/// 永続化・生成・register のロジックは `MobileTokenProvisioner`（AgentDomain）に委譲し、
/// ここは UI 状態とユーザー操作（再発行・QR 表示）だけを持つ。
/// 再発行時は `SessionTokenStore` への再 register まで行い、旧トークンを失効させる。
@MainActor
public final class MobileTokenViewModel: ObservableObject {
  /// 表示用トークン文字列（64hex）。永続化済みの値。
  @Published public private(set) var token: String

  /// 直近の再発行失敗を表すユーザー向けメッセージ。成功時・初期状態は nil。
  @Published public private(set) var lastError: String?

  /// QR ペアリング表示中か。明示操作で開始し、60 秒後に自動非表示。
  @Published public private(set) var isPairingQRVisible = false

  /// 直近に解決した露出範囲。回復・再解決で更新される。
  @Published public private(set) var bindMode: BindMode?

  /// 直近に解決したモバイルプロキシの待ち受けポート。回復・再解決で更新される。
  @Published public private(set) var mobileProxyPort: Int?

  private let provisioner: MobileTokenProvisioner
  private let tokenStore: SessionTokenStore
  private let proxy: MobileProxy
  private var current: ProvisionedMobileToken
  private var hidePairingQRTask: Task<Void, Never>?
  private var autoRecoveryTask: Task<Void, Never>?

  private static let logger = Logger(subsystem: "com.phlox.Phlox", category: "MobileToken")

  /// QR 表示の自動非表示までの秒数。
  private static let pairingQRVisibleDuration: TimeInterval = 60

  public init(
    provisioned: ProvisionedMobileToken,
    provisioner: MobileTokenProvisioner,
    tokenStore: SessionTokenStore,
    proxy: MobileProxy,
    bindMode: BindMode?,
    mobileProxyPort: Int?
  ) {
    self.current = provisioned
    self.token = provisioned.token.value
    self.provisioner = provisioner
    self.tokenStore = tokenStore
    self.proxy = proxy
    self.bindMode = bindMode
    self.mobileProxyPort = mobileProxyPort
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

  /// 表示要求のたびに `PairingPayload` を都度生成する（キャッシュしない）。
  public func makePairingPayload() -> Result<PairingPayload, PairingPayloadError> {
    guard let bindMode, let port = mobileProxyPort else {
      return .failure(.unsupportedBindMode)
    }
    return PairingPayload.make(
      bindMode: bindMode,
      port: port,
      token: token,
      name: Host.current().localizedName
    )
  }

  /// QR ペアリング表示を開始する。60 秒後に自動非表示。
  public func showPairingQR() {
    guard isPairingQREnabled else { return }
    isPairingQRVisible = true
    schedulePairingQRAutoHide()
  }

  /// QR ペアリング表示を手動で終了する。
  public func hidePairingQR() {
    hidePairingQRTask?.cancel()
    hidePairingQRTask = nil
    isPairingQRVisible = false
  }

  /// トークンを再発行する。旧トークンを失効させ、新トークンを SessionTokenStore へ再 register する。
  /// requester SessionID は安定のまま維持される。失敗時は `lastError` に公開し、os.Logger にも記録する
  /// （トークン値そのものはログへ残さない）。
  public func regenerate() async {
    do {
      let regenerated = try provisioner.regenerate()
      await provisioner.register(regenerated, into: tokenStore)
      current = regenerated
      token = regenerated.token.value
      lastError = nil
    } catch {
      lastError = String(localized: "トークンの再発行に失敗しました。しばらくしてから再度お試しください。")
      Self.logger.error("Mobile token regenerate failed: \(String(describing: error), privacy: .public)")
    }
  }

  deinit {
    hidePairingQRTask?.cancel()
    autoRecoveryTask?.cancel()
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
