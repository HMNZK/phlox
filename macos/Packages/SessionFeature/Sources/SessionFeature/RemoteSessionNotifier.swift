import Foundation

/// スマホへ渡す通知の種類。パソコンの通知と同じ種類にそろえる（C-62・B5）。
/// 承認の対象・質問文・エラー文などの本文の中身は渡さない（通知は Apple のサーバーを経由するため）。
public enum RemoteSessionNotification: Equatable, Sendable {
    case completed
    case approval
    case question
    case error
    case stalled
    /// ターミナル型のプロセスが 0 以外の終了コードで終わった（C-60）。
    case exited(code: Int32)
}

/// セッション完了・承認待ちをリモート通知系へ伝えるフック（APNs 送信は上位層の責務）。
/// 引数にメッセージ本文等の機密を含めない。
public protocol RemoteSessionNotifier: Sendable {
    func sessionCompleted(sessionId: String, sessionName: String)
    func approvalPending(sessionId: String, sessionName: String)
    /// 種類つきの通知。種類を区別しない送り先は、既定の実装で上の 2 つへ振り分ける。
    func notify(_ notification: RemoteSessionNotification, sessionId: String, sessionName: String)
}

public extension RemoteSessionNotifier {
    /// 種類を区別しない送り先への振り分け。無応答は従来どおり送らない。
    func notify(_ notification: RemoteSessionNotification, sessionId: String, sessionName: String) {
        switch notification {
        case .completed, .error, .exited:
            sessionCompleted(sessionId: sessionId, sessionName: sessionName)
        case .approval, .question:
            approvalPending(sessionId: sessionId, sessionName: sessionName)
        case .stalled:
            break
        }
    }
}
