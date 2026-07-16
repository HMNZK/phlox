import Foundation
import PhloxCore

public enum PairingConnectGate {
    /// QR ペアリング直後の「接続中…」を続けるか。
    /// - タイムアウト到達（elapsed >= timeout）なら false（listState に依らず最優先）。
    /// - listState が .loaded / .empty なら false（接続完了）。
    /// - listState が .loading / .offline / .error かつ elapsed < timeout なら true（継続）。
    public static func shouldContinueConnecting(
        listState: SessionsState,
        elapsed: TimeInterval,
        timeout: TimeInterval
    ) -> Bool {
        if elapsed >= timeout {
            return false
        }
        switch listState {
        case .loaded, .empty:
            return false
        case .loading, .offline, .error:
            return true
        }
    }

    /// 一覧が読めている（接続成功）か。`shouldContinueConnecting` が false を返したとき、
    /// それが成功（true）かタイムアウト失敗（false）かの判別に使う。
    public static func isConnected(listState: SessionsState) -> Bool {
        switch listState {
        case .loaded, .empty:
            return true
        case .loading, .offline, .error:
            return false
        }
    }
}
