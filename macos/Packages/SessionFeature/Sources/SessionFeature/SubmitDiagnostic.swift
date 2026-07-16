import Foundation
import AgentDomain

/// submit 後に「codex が処理状態へ入ったか」を一定時間観測し、観測できなかったとき
/// 1 行で記録する診断レコード。再発が稀な submit 滞留バグ(ADR 0002 §8.5)を、次に
/// 起きた瞬間に捕捉して真因特定するための observe-only 計装。status や完了検知は変えない。
struct SubmitDiagnostic {
    /// ISO8601 等のタイムスタンプ文字列(呼び出し側で生成し注入=テスト決定性のため)。
    let timestamp: String
    /// セッション短縮ラベル(#xxxxxx)。
    let sessionLabel: String
    let kind: AgentKind
    /// 送信本文のバイト数。
    let byteCount: Int
    /// bracketed paste で包んで送ったか。
    let bracketed: Bool
    /// 処理開始を待った秒数。
    let timeoutSeconds: Double
    /// タイムアウト時点の可視テキスト末尾(滞留有無の判断材料)。
    let visibleTail: String

    /// grep しやすい 1 行ログ。可視テキスト末尾の改行は ⏎ に潰して 1 行に収める。
    var logLine: String {
        let flatTail = visibleTail
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\r", with: "")
        return "[\(timestamp)] submit-no-processing session=\(sessionLabel) kind=\(kind) "
            + "bytes=\(byteCount) bracketed=\(bracketed) timeout=\(timeoutSeconds)s tail=\(flatTail)"
    }
}
