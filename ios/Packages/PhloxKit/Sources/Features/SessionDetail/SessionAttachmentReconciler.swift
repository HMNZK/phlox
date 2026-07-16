import PhloxCore

enum SessionAttachmentReconciler {
    struct Pending: Equatable, Sendable {
        let text: String
        let count: Int

        init(text: String, count: Int) {
            self.text = text
            self.count = count
        }
    }

    /// 各 pending を「送信テキストに一致する最新の未割当ユーザーメッセージ」へ割り当てる。
    /// messages を末尾から走査し、`.user(id,text)` かつ text 一致かつ id が結果マップ未登録の最初のものへ count を割当。
    /// 一致が無ければ pending を remaining に残す。既に割当済みの id は再割当しない（同一 pass 内の二重割当もしない）。
    /// 戻り assigned は入力 assigned に新規割当をマージした全体マップ。
    static func reconcile(
        messages: [ChatMessage],
        pending: [Pending],
        assigned: [String: Int]
    ) -> (assigned: [String: Int], remaining: [Pending]) {
        var resultAssigned = assigned
        var remaining: [Pending] = []

        for item in pending {
            var matched = false
            for message in messages.reversed() {
                guard case let .user(id, text) = message, text == item.text else { continue }
                guard resultAssigned[id] == nil else { continue }
                resultAssigned[id] = item.count
                matched = true
                break
            }
            if !matched {
                remaining.append(item)
            }
        }

        return (resultAssigned, remaining)
    }
}
