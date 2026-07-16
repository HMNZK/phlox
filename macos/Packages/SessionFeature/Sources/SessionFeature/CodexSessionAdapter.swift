import Foundation
import AgentDomain

/// codex CLI 固有の出力監視ロジックを SessionViewModel から分離したクラス。
/// ディレクトリ信頼プロンプトの自動応答状態と対話的質問（承認 / elicitation）の検出状態を保持し、
/// 可視テキストと現在の status から「VM が行うべき遷移」を決定する。
/// 副作用（status 変更・PTY 書込・通知）は SessionViewModel 側で適用する。
@MainActor
final class CodexSessionAdapter {
    /// codex は per-session ディレクトリで起動するとディレクトリ信頼プロンプトでブロックする。
    /// この文言を検出したら自動で Enter（既定の Yes, continue）を送って先へ進める（ADR 0002）。
    static let trustPromptMarker = "Do you trust the contents"

    /// 信頼プロンプトへ二重に Enter を送らないためのガード（restart でリセット）。
    private(set) var didAutoAnswerTrustPrompt = false
    /// 質問（承認/elicitation）プロンプトの表示を検出して回答待ちに入っているか。
    private(set) var isAwaitingQuestion = false
    /// 回答待ち中にユーザー入力（送信）を観測したか。質問マーカー消失と組で running 復帰を判定する。
    private var questionAnswerSubmitted = false

    /// 質問検知の判定結果。SessionViewModel が status 遷移・通知へ変換する。
    enum QuestionAction: Equatable {
        case none
        /// 新たに質問を検出した。running 起点（ターン途中の質問）なら入力待ち通知を出す。
        case enterAwaiting(notifyAwaitingInput: Bool)
        /// 質問が可視のまま。hook イベント等で巻き戻った status を awaiting へ再整合する。
        case reassertAwaiting
        /// 回答送信後に質問が消えた。awaiting なら running へ戻す。
        case resumeRunning
    }

    /// codex が処理中(ターン進行中)であることを示す可視テキストのトークン。
    /// 複数の OR で判定し、UI 文言の小変更に多少頑健にする(ADR 0002 §8.6 の計装)。
    nonisolated static let processingMarkers = ["esc to interrupt", "Working", "Thinking"]

    /// 可視テキストが「codex が処理中」を示すか。submit 後に一度でも true を観測できれば
    /// その送信は submit 成立とみなせる。観測専用(status は変えない)。純関数のため nonisolated。
    nonisolated static func indicatesProcessing(in visibleText: String) -> Bool {
        processingMarkers.contains { visibleText.contains($0) }
    }

    /// 信頼プロンプトが可視かつ未応答なら true を返し、応答済みとして記録する。
    /// 応答済みのときは可視テキストを評価せず即 false（自動応答チェックのスキップ）。
    func consumeTrustPromptAutoAnswer(visibleText: @autoclosure () -> String) -> Bool {
        guard !didAutoAnswerTrustPrompt else { return false }
        guard visibleText().contains(Self.trustPromptMarker) else { return false }
        didAutoAnswerTrustPrompt = true
        return true
    }

    /// 可視テキストと現在 status から質問検知の状態を進め、VM が適用すべき遷移を返す。
    func reconcileQuestion(visibleText: String, status: SessionStatus) -> QuestionAction {
        let visible = CodexQuestionDetector.isQuestionVisible(in: visibleText)

        if visible && !isAwaitingQuestion {
            switch status {
            case .running, .idle:
                // running→awaiting はターン途中の質問で、完了通知(running→idle)が鳴らない系統。
                // そこだけ入力待ち通知を出す。idle→awaiting は直前に完了通知が鳴っている想定で二重通知を避ける。
                let cameFromRunning = (status == .running)
                isAwaitingQuestion = true
                questionAnswerSubmitted = false
                return .enterAwaiting(notifyAwaitingInput: cameFromRunning)
            default:
                return .none
            }
        }

        if visible && isAwaitingQuestion {
            switch status {
            case .completed, .error, .awaitingApproval:
                return .none
            default:
                return .reassertAwaiting
            }
        }

        if !visible && isAwaitingQuestion && questionAnswerSubmitted {
            isAwaitingQuestion = false
            questionAnswerSubmitted = false
            return .resumeRunning
        }

        return .none
    }

    /// 入力送信を観測したとき呼ぶ。質問待ち中なら「回答送信済み」を記録する。
    func noteInputSubmitted() {
        if isAwaitingQuestion {
            questionAnswerSubmitted = true
        }
    }

    /// restart 時に全状態をリセットする。
    func reset() {
        didAutoAnswerTrustPrompt = false
        isAwaitingQuestion = false
        questionAnswerSubmitted = false
    }
}
