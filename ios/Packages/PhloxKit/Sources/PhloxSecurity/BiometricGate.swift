import Foundation
import LocalAuthentication
import PhloxCore

/// Face ID / Touch ID による起動ゲート（E3-3）。`Authenticating` 実装。
///
/// 生体認証が使える端末では生体を、使えない端末ではパスコード（`deviceOwnerAuthentication`）に
/// fallback する。認証の評価前に API クライアントを呼ばないことは AppModel（E4-1）が保証する。
public struct BiometricGate: Authenticating {
    public init() {}

    /// 生体評価可否からポリシーを決める純粋関数（テスト可能）。
    /// 生体可 → 生体、不可 → パスコード fallback。
    static func policy(canEvaluateBiometrics: Bool) -> LAPolicy {
        canEvaluateBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
    }

    public func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var evalError: NSError?
        let canBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evalError)
        let policy = Self.policy(canEvaluateBiometrics: canBiometrics)

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: AuthenticationError.failed(String(describing: error)))
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

public enum AuthenticationError: Error, Equatable {
    case failed(String)
}
