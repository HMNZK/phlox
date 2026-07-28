import Foundation

/// composer（入力欄）へキーボードフォーカスを戻す要求。
///
/// esc 2連打 → 履歴ピッカー → 過去メッセージ選択（または キャンセル）のあと、ユーザーがマウスで
/// 入力欄をクリックし直さずタイプを再開できるようにするための、ViewModel → View の一方向シグナル。
///
/// PM 凍結面（tasks/task-1.md / tasks/task-2.md 契約）。実装役はこのファイルを変更しない。
/// - task-1 が `ChatSessionViewModel.composerFocusRequest` を適切な瞬間に発火させる。
/// - task-2 が `IMESafeTextView` でこれを受け取り、実際に first responder とキャレットを動かす。
public struct ComposerFocusRequest: Equatable, Sendable {
    /// 単調増加のトークン。View は「直前に処理した値から変化したとき」だけフォーカス移動を実行する。
    /// 再描画のたびにフォーカスを奪い返さないための冪等キーであり、値そのものに意味は無い。
    public let token: Int

    /// キャレットを本文末尾へ移すか。本文を復元した経路だけ true。
    /// false のときは View はキャレット・選択範囲を動かしてはならない。
    public let movesCaretToEnd: Bool

    /// 未要求の初期値。この値のあいだ View はフォーカスを奪わない。
    public static let none = ComposerFocusRequest(token: 0, movesCaretToEnd: false)

    public init(token: Int, movesCaretToEnd: Bool) {
        self.token = token
        self.movesCaretToEnd = movesCaretToEnd
    }
}
