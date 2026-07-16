import Foundation

/// `PhloxError` をユーザー向けに提示するための、タイトル・本文・回復アクション文言。
/// UI（E4-x / E5-2）はこれを使ってエラーバナーやリトライ導線を組み立てる。
public struct ErrorPresentation: Sendable, Equatable {
    public let title: String
    public let message: String
    /// 回復アクションのボタン文言（なければ nil）。
    public let recoveryAction: String?

    public init(title: String, message: String, recoveryAction: String?) {
        self.title = title
        self.message = message
        self.recoveryAction = recoveryAction
    }
}

public extension PhloxError {
    /// ユーザー向け提示情報へ変換する。全ケースで非空のタイトル・本文を返す。
    var presentation: ErrorPresentation {
        switch self {
        case .unauthorized:
            return ErrorPresentation(
                title: "認証が必要です",
                message: "トークンが無効か期限切れです。接続設定からトークンを再設定してください。",
                recoveryAction: "接続設定を開く"
            )
        case .unreachable:
            return ErrorPresentation(
                title: "Mac に接続できません",
                message: "ネットワークが圏外か、Mac がスリープしている可能性があります。",
                recoveryAction: "再試行"
            )
        case .rateLimited(let retryAfter):
            return ErrorPresentation(
                title: "混雑しています",
                message: "リクエストが多すぎます。\(retryAfter) 秒後に再試行してください。",
                recoveryAction: "再試行"
            )
        case .spawnRejected(let reason):
            return ErrorPresentation(
                title: "セッションを開始できません",
                message: reason,
                recoveryAction: nil
            )
        case .notFound:
            return ErrorPresentation(
                title: "見つかりません",
                message: "対象のセッションは削除されたか存在しません。",
                recoveryAction: "一覧に戻る"
            )
        case .server(let status, let message):
            return ErrorPresentation(
                title: "サーバエラー (\(status))",
                message: message ?? "Mac 側で問題が発生しました。しばらくして再試行してください。",
                recoveryAction: "再試行"
            )
        case .decoding(let wrapped):
            return ErrorPresentation(
                title: "応答を解釈できません",
                message: "Mac 側との形式が一致しません。アプリ/サーバの更新が必要かもしれません。(\(wrapped.description))",
                recoveryAction: nil
            )
        case .transport(let wrapped):
            return ErrorPresentation(
                title: "通信エラー",
                message: "通信中に問題が発生しました。(\(wrapped.description))",
                recoveryAction: "再試行"
            )
        }
    }
}
