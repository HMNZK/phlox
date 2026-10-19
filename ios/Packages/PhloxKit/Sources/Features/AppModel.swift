import SwiftUI
import PhloxCore

/// 接続待ちが失敗した（タイムアウトで一覧に到達できなかった）ときに画面へ出す原因情報。
public struct ConnectFailure: Equatable, Sendable {
    public let title: String
    public let message: String
    public let nextStep: String?
    public let detail: String?
    public let isNeutral: Bool
    public let checklist: [String]

    public init(
        title: String,
        message: String,
        nextStep: String? = nil,
        detail: String? = nil,
        isNeutral: Bool = false,
        checklist: [String] = []
    ) {
        self.title = title
        self.message = message
        self.nextStep = nextStep
        self.detail = detail
        self.isNeutral = isNeutral
        self.checklist = checklist
    }
}

/// アプリ全体のルート分岐を司る状態モデル（E4-10 / DP-4-10）。
/// 認証 → 接続設定 → セッションの 3 段階を `state` に集約する。到達不可は一覧オーバーレイで表現する。
@MainActor
@Observable
public final class AppModel {
    public enum AuthState: Sendable, Equatable {
        case locked
        case unlocked
    }

    /// ルート画面の分岐。`AppRoot` がこれを見て表示を切り替える。
    public enum AppState: Sendable, Equatable {
        case locked
        case setupRequired
        case sessions
    }

    public var authState: AuthState = .locked
    /// 接続設定（host/port + トークン）が揃っているか。
    public var hasConnectionConfig: Bool = false
    public var reachability: Reachability = .unknown
    /// QR ペアリング直後の到達性再判定中フラグ。true の間は全画面「接続中…」を出す。
    public var isConnecting: Bool = false
    /// 接続待ちがタイムアウトで失敗したときの原因（画面表示用）。nil の間はリッチな接続中アニメーションを出す。
    public var connectFailure: ConnectFailure?
    public var connectionWaitSeconds = 0
    public var connectedMacName = "Mac"

    /// Pairing URL は起動時設定の復元とロック解除が完了するまでルーティングしない。
    public func canOpenPairingURL(bootstrapComplete: Bool) -> Bool {
        bootstrapComplete && authState == .unlocked
    }

    public init(
        authState: AuthState = .locked,
        hasConnectionConfig: Bool = false,
        reachability: Reachability = .unknown,
        isConnecting: Bool = false,
        connectFailure: ConnectFailure? = nil
    ) {
        self.authState = authState
        self.hasConnectionConfig = hasConnectionConfig
        self.reachability = reachability
        self.isConnecting = isConnecting
        self.connectFailure = connectFailure
    }

    /// 現在のルート状態。
    public var state: AppState {
        Self.resolve(authState: authState, hasConnectionConfig: hasConnectionConfig, reachability: reachability)
    }

    /// 認証ゲートを優先する。接続処理と失敗情報はロック中も保持する。
    public var showsConnectingOverlay: Bool {
        isConnecting && authState == .unlocked
    }

    /// 3 段階分岐の純粋ロジック（テスト可能）。
    /// 未認証→locked、未設定→setupRequired、それ以外→sessions（到達不可は一覧内オーバーレイ）。
    public static func resolve(
        authState: AuthState,
        hasConnectionConfig: Bool,
        reachability: Reachability
    ) -> AppState {
        guard authState == .unlocked else { return .locked }
        guard hasConnectionConfig else { return .setupRequired }
        _ = reachability
        return .sessions
    }

    public static func initialAuthState(faceIDEnabled: Bool) -> AuthState {
        faceIDEnabled ? .locked : .unlocked
    }

    public static func shouldRelock(scenePhase: ScenePhase, faceIDEnabled: Bool) -> Bool {
        faceIDEnabled && scenePhase == .background
    }
}
