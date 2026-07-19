import Foundation

/// task-0 契約（凍結・PM 著）: AskUserQuestion のモバイル向けワイヤ契約。
/// 定数はワイヤ形状の単一の正（iOS 側 `PhloxQuestionWireContract` と一字一句一致させる）。
/// `implemented` は task-3（macOS 側配線）の実装完了と同時に true へ反転する
/// （flag だけの反転は虚偽報告として扱う）。
///
/// メッセージ側（GET /sessions/{id}/messages の ChatMessageDTO）:
///   type == "userQuestion" のとき追加フィールド
///   {"requestId": String, "state": "pending"|"answered"|"expired",
///    "questions": [{"question","header","multiSelect","options":[{"label","description"?}]}],
///    "answers": {"<question文>": [String]}? }
/// 回答側:
///   POST /sessions/{id}/question  body {"requestId": String, "answers": {"<question文>": [String]}}
///   → 200（受理）/ 404（セッション or pending 質問なし）/ 400（body 不正）
public enum ControlQuestionWireContract {
    public static let messageType = "userQuestion"
    public static let questionPathSuffix = "/question"
    public static let requestIdKey = "requestId"
    public static let stateKey = "state"
    public static let questionsKey = "questions"
    public static let answersKey = "answers"
    public static let questionKey = "question"
    public static let headerKey = "header"
    public static let multiSelectKey = "multiSelect"
    public static let optionsKey = "options"
    public static let optionLabelKey = "label"
    public static let optionDescriptionKey = "description"
    public static let statePending = "pending"
    public static let stateAnswered = "answered"
    public static let stateExpired = "expired"
    public static let implemented = false
}
