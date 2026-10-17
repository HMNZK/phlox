import Foundation

/// 入力欄の送信可否判定。
enum DSSubmitBarLogic {
    /// 送信可能か: 空白のみ・送信中は不可。
    static func canSubmit(text: String, isLoading: Bool) -> Bool {
        !isLoading && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
