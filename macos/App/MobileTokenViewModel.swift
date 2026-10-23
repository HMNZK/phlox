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
  /// 端末ごとの最後の要求の時刻（接続中の判定用。保存しない）。3 秒ごとの要求で画面を描き直さないよう、10 秒に 1 回だけ進める。
  @Published public private(set) var lastSeenAt: [UUID: Date] = [:]

  /// 直近の発行・失効失敗を表すユーザー向けメッセージ。成功時・初期状態は nil。
  @Published public private(set) var lastError: String?

  /// QR ペアリング表示中か。明示操作で開始し、60 秒後に自動非表示。
  @Published public private(set) var isPairingQRVisible = false
  /// QR を自動で隠す時刻（設定画面の「あと 0:48 で非表示」に使う）。表示中だけ値を持つ。
  @Published public private(set) var pairingQRHidesAt: Date?

  /// 直近に解決した露出範囲。回復・再解決で更新される。
  @Published public private(set) var bindMode: BindMode?

  /// 直近に解決したモバイルプロキシの待ち受けポート。回復・再解決で更新される。
  @Published public private(set) var mobileProxyPort: Int?
  /// スマホへの通知を送る鍵がそろっているか（設定「プッシュ通知」の注記、C-55）。
  @Published public var isPushSendingConfigured = true

  public typealias RuntimeCommandHandler = @MainActor (MobileRuntimeCommand) async throws -> MobileRuntimeReply

  private struct OwnedDependencies {
    let provisioner: MobileDeviceProvisioner
    let tokenStore: SessionTokenStore
    let proxy: MobileProxy
    let onPrivilegedRequestersChanged: (Set<SessionID>) -> Void
  }

  private enum Backing {
    case owned(OwnedDependencies)
    case projected(RuntimeCommandHandler)
  }

  private let backing: Backing
  /// 直近に「QR を表示」で発行した端末のトークン。QR 画像の生成にのみ使う（表示・コピーはしない）。
  private var pendingQRToken: String?
  private var hidePairingQRTask: Task<Void, Never>?
  private var autoRecoveryTask: Task<Void, Never>?
  private var runtimeRevision: UInt64 = 0
  private var projectedHostName: String?

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
    self.backing = .owned(OwnedDependencies(
      provisioner: provisioner,
      tokenStore: tokenStore,
      proxy: proxy,
      onPrivilegedRequestersChanged: onPrivilegedRequestersChanged
    ))
    self.bindMode = bindMode
    self.mobileProxyPort = mobileProxyPort
  }

  public init(snapshot: MobileRuntimeSnapshot, commandHandler: @escaping RuntimeCommandHandler) {
    backing = .projected(commandHandler)
    applyRuntimeSnapshot(snapshot)
  }

  public func makeRuntimeSnapshot() -> MobileRuntimeSnapshot {
    if case .owned = backing { runtimeRevision += 1 }
    return MobileRuntimeSnapshot(
      revision: runtimeRevision,
      devices: devices.map(MobileRuntimeSnapshot.Device.init),
      lastSeenAt: lastSeenAt,
      lastError: lastError,
      exposure: bindMode.map(MobileRuntimeSnapshot.Exposure.init),
      mobileProxyPort: mobileProxyPort,
      isPushSendingConfigured: isPushSendingConfigured,
      isPairingQRVisible: isPairingQRVisible,
      pairingQRHidesAt: pairingQRHidesAt,
      pendingQRToken: isPairingQRVisible ? pendingQRToken : nil,
      hostName: pairingHostName
    )
  }

  public func applyRuntimeSnapshot(_ snapshot: MobileRuntimeSnapshot) {
    guard case .projected = backing, snapshot.revision >= runtimeRevision else { return }
    runtimeRevision = snapshot.revision
    devices = snapshot.devices.map(\.pairedDevice)
    lastSeenAt = snapshot.lastSeenAt
    lastError = snapshot.lastError
    bindMode = snapshot.exposure?.bindMode
    mobileProxyPort = snapshot.mobileProxyPort
    isPushSendingConfigured = snapshot.isPushSendingConfigured
    hidePairingQRTask?.cancel()
    hidePairingQRTask = nil
    let visibleUntil = snapshot.pairingQRHidesAt.flatMap { $0 > Date() ? $0 : nil }
    isPairingQRVisible = snapshot.isPairingQRVisible && visibleUntil != nil
    pairingQRHidesAt = isPairingQRVisible ? visibleUntil : nil
    pendingQRToken = isPairingQRVisible ? snapshot.pendingQRToken : nil
    projectedHostName = snapshot.hostName
    if isPairingQRVisible, let visibleUntil {
      schedulePairingQRAutoHide(at: visibleUntil)
    }
  }

  public func performRuntimeCommand(_ command: MobileRuntimeCommand) async throws -> MobileRuntimeReply {
    guard case .owned = backing else { throw MobileRuntimeError.projectionCannotPerformOwnedCommand }
    switch command {
    case .showPairingQR(let deviceName): await showPairingQR(deviceName: deviceName)
    case .hidePairingQR: hidePairingQR()
    case .revoke(let id): await revoke(id: id)
    case .refreshReachability: await refreshReachability()
    case .startAutoRecovery: startAutoRecovery()
    }
    return MobileRuntimeReply(snapshot: makeRuntimeSnapshot())
  }

  private var pairingHostName: String? {
    switch backing {
    case .owned: Host.current().localizedName
    case .projected: projectedHostName
    }
  }

  private func sendRuntimeCommand(_ command: MobileRuntimeCommand) async {
    guard case .projected(let handler) = backing else { return }
    do {
      let reply = try await handler(command)
      applyRuntimeSnapshot(reply.snapshot)
    } catch {
      lastError = "常駐プロセスとの通信に失敗しました。操作の結果を確認できません。"
      Self.logger.error("Mobile runtime command failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// オンデマンドで Tailscale 到達性を再解決し、UI 向け状態へ反映する。
  public func refreshReachability() async {
    guard case .owned(let owned) = backing else {
      await sendRuntimeCommand(.refreshReachability)
      return
    }
    let refreshedBindMode = await owned.proxy.refresh()
    let refreshedPort = await owned.proxy.boundPort.map(Int.init)
    bindMode = refreshedBindMode
    mobileProxyPort = refreshedPort
  }

  /// 起動直後の短い自動回復を一度だけ駆動する。既に Tailscale 到達済みなら何もしない。
  public func startAutoRecovery() {
    guard case .owned(let owned) = backing else {
      Task { [weak self] in await self?.sendRuntimeCommand(.startAutoRecovery) }
      return
    }
    if case .tailscale = bindMode { return }
    guard autoRecoveryTask == nil else { return }

    autoRecoveryTask = Task { [weak self] in
      guard let self else { return }
      let recoveredBindMode = await owned.proxy.recoverUntilReachable(
        maxAttempts: 5,
        delay: .seconds(2)
      )
      let recoveredPort = await owned.proxy.boundPort.map(Int.init)
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
      name: pairingHostName
    )
  }

  /// 新しい端末を発行し QR 表示を開始する。既存端末の token / requester には触れない。
  /// 60 秒後に自動非表示。
  public func showPairingQR(deviceName: String) async {
    guard case .owned(let owned) = backing else {
      await sendRuntimeCommand(.showPairingQR(deviceName: deviceName))
      return
    }
    guard isPairingQREnabled else { return }
    do {
      let device = try owned.provisioner.issueDevice(name: deviceName)
      await owned.provisioner.syncRegistrations(into: owned.tokenStore)
      try reloadDevicesAndPrivilegedRequesters()
      pendingQRToken = device.token.value
      lastError = nil
      isPairingQRVisible = true
      schedulePairingQRAutoHide()
    } catch {
      lastError = "端末の発行に失敗しました。しばらくしてから再度お試しください。"
      Self.logger.error("Mobile device issue failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// QR ペアリング表示を手動で終了する。
  public func hidePairingQR() {
    guard case .owned = backing else {
      Task { [weak self] in await self?.sendRuntimeCommand(.hidePairingQR) }
      return
    }
    hidePairingQRTask?.cancel()
    hidePairingQRTask = nil
    isPairingQRVisible = false
    pairingQRHidesAt = nil
    pendingQRToken = nil
  }

  /// 端末を 1 台失効させる。失効後は `SessionTokenStore` への登録も取り消し、一覧を更新する。
  public func revoke(id: UUID) async {
    guard case .owned(let owned) = backing else {
      await sendRuntimeCommand(.revoke(id: id))
      return
    }
    do {
      try owned.provisioner.revoke(id: id)
      await owned.provisioner.syncRegistrations(into: owned.tokenStore)
      try reloadDevicesAndPrivilegedRequesters()
      lastError = nil
    } catch {
      lastError = "端末の失効に失敗しました。しばらくしてから再度お試しください。"
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
    guard case .owned = backing else { return }
    do {
      try reloadDevicesAndPrivilegedRequesters()
      // 表示中の QR の端末が成立したら、フルアクセスのトークンを画面に残さず閉じる（10 Settings）。
      if isPairingQRVisible, devices.contains(where: { $0.token.value == pendingQRToken && $0.pairedAt != nil }) {
        hidePairingQR()
      }
    } catch {
      Self.logger.error("Mobile device list refresh after pairing failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// 認証が通った要求のトークンから端末を引き、最後の要求の時刻を進める（C-54）。
  public func noteSeen(token: String, at date: Date = Date()) {
    guard case .owned = backing else { return }
    guard let device = devices.first(where: { $0.token.value == token }) else { return }
    if let last = lastSeenAt[device.id], date.timeIntervalSince(last) < 10 { return }
    lastSeenAt[device.id] = date
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
    guard case .owned(let owned) = backing else { throw MobileRuntimeError.projectionCannotPerformOwnedCommand }
    devices = try owned.provisioner.loadAndMigrate()
    owned.onPrivilegedRequestersChanged(MobileBootstrap.privilegedRequesters(for: devices))
  }

  private func schedulePairingQRAutoHide(at deadline: Date? = nil) {
    hidePairingQRTask?.cancel()
    let hidesAt = deadline ?? Date().addingTimeInterval(Self.pairingQRVisibleDuration)
    pairingQRHidesAt = hidesAt
    hidePairingQRTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(max(0, hidesAt.timeIntervalSinceNow))) }
      catch { return }
      guard !Task.isCancelled, let self else { return }
      self.isPairingQRVisible = false
      self.pairingQRHidesAt = nil
      self.pendingQRToken = nil
      self.hidePairingQRTask = nil
    }
  }
}
