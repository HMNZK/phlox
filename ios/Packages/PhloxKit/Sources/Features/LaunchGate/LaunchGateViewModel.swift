import SwiftUI
import PhloxCore

/// 起動ゲート（カンプ⑥ / E4-1）。生体認証成功まで API 接続をブロックする。
/// 依存は `Authenticating` のみ（API クライアントを持たない＝認証前にネットワークを叩けない設計）。
@MainActor
@Observable
public final class LaunchGateViewModel {
    public enum State: Equatable {
        case idle
        case authenticating
        case failed(String)
        case unlocked
    }

    private let authenticator: Authenticating
    public var state: State = .idle

    public init(authenticator: Authenticating) {
        self.authenticator = authenticator
    }

    public var isUnlocked: Bool { state == .unlocked }
    public var errorMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    public func authenticate() async {
        state = .authenticating
        do {
            let success = try await authenticator.authenticate(reason: "Phlox のロックを解除")
            state = success ? .unlocked : .failed("認証に失敗しました。もう一度お試しください。")
        } catch {
            state = .failed("認証に失敗しました。もう一度お試しください。")
        }
    }
}
