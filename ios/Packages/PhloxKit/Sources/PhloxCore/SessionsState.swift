import Foundation

/// セッション一覧画面（カンプ②/⑩/⑪）の有限状態。ViewModel はこの 1 型だけを見る。
public enum SessionsState: Sendable, Equatable {
    case loading
    case loaded([Session])
    case empty
    case offline
    case error(PhloxError)
}
