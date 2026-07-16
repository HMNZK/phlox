import Foundation

/// 送信バー共通の送信可否判定（`DSInputBar` / `DSChatInputBar`）。
enum DSSubmitBarLogic {
    /// 送信可能か: 空白のみ・送信中は不可。
    static func canSubmit(text: String, isLoading: Bool) -> Bool {
        !isLoading && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
