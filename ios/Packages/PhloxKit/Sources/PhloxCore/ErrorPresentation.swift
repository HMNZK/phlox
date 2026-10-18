import Foundation

/// `PhloxError` をユーザー向けに提示するための、タイトル・本文・回復アクション文言。
/// UI（E4-x / E5-2）はこれを使ってエラーバナーやリトライ導線を組み立てる。
public struct ErrorPresentation: Sendable, Equatable {
    public let title: String
    public let cause: String
    public let nextStep: String
    public let technicalDetail: String?
    /// 回復アクションのボタン文言（なければ nil）。
    public let recoveryAction: String?
    public let isNeutral: Bool

    public var message: String {
        [cause, nextStep].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public init(
        title: String,
        message: String,
        recoveryAction: String?,
        nextStep: String = "",
        technicalDetail: String? = nil,
        isNeutral: Bool = false
    ) {
        self.title = title
        self.cause = message
        self.nextStep = nextStep
        self.technicalDetail = technicalDetail
        self.recoveryAction = recoveryAction
        self.isNeutral = isNeutral
    }
}

public extension PhloxError {
    /// ユーザー向け提示情報へ変換する。全ケースで非空のタイトル・本文を返す。
    var presentation: ErrorPresentation {
        switch self {
        case .unauthorized:
            return ErrorPresentation(
                title: "Mac に接続を断られました",
                message: "この iPhone に保存した接続の鍵（トークン）が、Mac 側で使えなくなっています。",
                recoveryAction: "QR で再接続",
                nextStep: "Mac で QR を表示し、読み取り直してください。",
                technicalDetail: "HTTP 401 Unauthorized"
            )
        case .unreachable:
            return ErrorPresentation(
                title: "Mac に届きません",
                message: "Mac がスリープしているか、Mac か iPhone の Tailscale が切れています。",
                recoveryAction: "再試行",
                nextStep: "Mac を起こし、Tailscale をオンにしてから再試行してください。",
                technicalDetail: "Mac から応答がありません"
            )
        case .rateLimited(let retryAfter):
            return ErrorPresentation(
                title: "Mac が混み合っています",
                message: "短い間に要求が集中したため、Mac が受け付けを止めています。",
                recoveryAction: "再試行（\(retryAfter) 秒）",
                nextStep: "\(retryAfter) 秒後に再試行できます。",
                technicalDetail: "HTTP 429 · Retry-After: \(retryAfter)",
                isNeutral: true
            )
        case .spawnRejected(let reason):
            return ErrorPresentation(
                title: "セッションを作れませんでした",
                message: "Mac がこの作成を受け付けませんでした。Mac にセッションは作られていません。",
                recoveryAction: "送信",
                nextStep: "理由を確かめてから、もう一度送信してください。指示は入力欄に戻してあります。",
                technicalDetail: reason
            )
        case .notFound:
            return ErrorPresentation(
                title: "このセッションは見つかりません",
                message: "Mac 側で削除されたか、終了して片付けられました。",
                recoveryAction: "一覧に戻る",
                nextStep: "一覧に戻って、ほかのセッションを開いてください。",
                technicalDetail: "HTTP 404"
            )
        case .unsupported:
            return ErrorPresentation(
                title: "Mac の応答を読めません",
                message: "iPhone と Mac の Phlox のバージョンが合っていないと起きます。",
                recoveryAction: nil,
                nextStep: "App Store と Mac の両方で Phlox を最新にしてください。",
                technicalDetail: "この機能は接続先の Mac に対応していません"
            )
        case .server(let status, let message):
            return ErrorPresentation(
                title: "Mac の Phlox でエラーが起きました",
                message: "要求を処理している途中で、Mac 側で問題が起きました。",
                recoveryAction: "再試行",
                nextStep: "少し待って再試行してください。続くときは Mac の Phlox を再起動してください。",
                technicalDetail: message.map { "HTTP \(status) \($0)" } ?? "HTTP \(status)"
            )
        case .decoding(let wrapped):
            return ErrorPresentation(
                title: "Mac の応答を読めません",
                message: "iPhone と Mac の Phlox のバージョンが合っていないと起きます。",
                recoveryAction: nil,
                nextStep: "App Store と Mac の両方で Phlox を最新にしてください。",
                technicalDetail: "decode: \(wrapped.description)"
            )
        case .transport(let wrapped):
            return ErrorPresentation(
                title: "通信が途中で切れました",
                message: "電波が弱いか、Wi‑Fi とモバイル通信が切り替わりました。",
                recoveryAction: "再試行",
                nextStep: "通信が落ち着いたら再試行してください。",
                technicalDetail: wrapped.description
            )
        }
    }
}
