import AgentDomain
import Foundation
import MobileProxy

/// 端末tokenとQR tokenを含む。認証済みdesktop管理経路だけで運ぶ。
public struct MobileRuntimeSnapshot: Codable, Equatable, Sendable {
  public struct Device: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let token: String
    public let requesterSessionID: UUID
    public let issuedAt: Date
    public let pairedAt: Date?

    init(_ device: PairedDevice) {
      id = device.id
      name = device.name
      token = device.token.value
      requesterSessionID = device.requesterSessionID.rawValue
      issuedAt = device.issuedAt
      pairedAt = device.pairedAt
    }

    var pairedDevice: PairedDevice {
      PairedDevice(
        id: id, name: name, token: MobileToken(value: token),
        requesterSessionID: SessionID(rawValue: requesterSessionID), issuedAt: issuedAt, pairedAt: pairedAt
      )
    }
  }

  public enum Exposure: Codable, Equatable, Sendable {
    case tailscale(String)
    case loopbackOnly
    case explicitHost(String)

    init(_ mode: BindMode) {
      switch mode {
      case .tailscale(let address): self = .tailscale(address)
      case .loopbackOnly: self = .loopbackOnly
      case .explicitHost(let address): self = .explicitHost(address)
      }
    }

    var bindMode: BindMode {
      switch self {
      case .tailscale(let address): .tailscale(address)
      case .loopbackOnly: .loopbackOnly
      case .explicitHost(let address): .explicitHost(address)
      }
    }
  }

  public let revision: UInt64
  public let devices: [Device]
  public let lastSeenAt: [UUID: Date]
  public let lastError: String?
  public let exposure: Exposure?
  public let mobileProxyPort: Int?
  public let isPushSendingConfigured: Bool
  public let isPairingQRVisible: Bool
  public let pairingQRHidesAt: Date?
  public let pendingQRToken: String?
  public let hostName: String?
}

public enum MobileRuntimeCommand: Codable, Equatable, Sendable {
  case showPairingQR(deviceName: String)
  case hidePairingQR
  case revoke(id: UUID)
  case refreshReachability
  case startAutoRecovery
}

public struct MobileRuntimeReply: Codable, Equatable, Sendable {
  public let snapshot: MobileRuntimeSnapshot

  public init(snapshot: MobileRuntimeSnapshot) {
    self.snapshot = snapshot
  }
}

public enum MobileRuntimeError: Error {
  case projectionCannotPerformOwnedCommand
}
