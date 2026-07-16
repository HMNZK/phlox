import Foundation

/// セッション完了・承認待ちをリモート通知系へ伝えるフック（APNs 送信は上位層の責務）。
/// 引数にメッセージ本文等の機密を含めない。
public protocol RemoteSessionNotifier: Sendable {
    func sessionCompleted(sessionId: String, sessionName: String)
    func approvalPending(sessionId: String, sessionName: String)
}
