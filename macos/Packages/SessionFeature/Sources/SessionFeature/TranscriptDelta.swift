import Foundation
import StructuredChatKit

/// `/sessions/{id}/messages` の差分取得（契約6）結果。
/// - `items`: このレスポンスで返す ChatItem 群（差分なら新規分のみ、全量なら transcript 全体）
/// - `cursor`: 不透明な位置カーソル（クライアントは解釈しない）。同一内容なら同一文字列・変化で前進する
/// - `isSnapshot`: 全量スナップショットへフォールバックしたか（差分の健全性を保証できない場合 true）
public struct TranscriptDelta: Equatable {
    public let items: [ChatItem]
    public let cursor: String
    public let isSnapshot: Bool

    public init(items: [ChatItem], cursor: String, isSnapshot: Bool) {
        self.items = items
        self.cursor = cursor
        self.isSnapshot = isSnapshot
    }
}

/// カーソルの符号化と、prefix 安定性の判定に使う内容ハッシュ。
///
/// 設計の要（正しさハザード対策）: transcript は append 専用ではなく `appendOrReplace` で既存項目の
/// 編集・置換が起きる。差分の健全性は「カーソル発行時に見えていた prefix が、その後も一切変化して
/// いない」ことを **現在の実データから毎回再計算して照合**することで保証する。内部に増分追跡の状態を
/// 持たない（＝どの変更経路を通っても取りこぼしが起きない）。少しでも不一致・不整合を検出したら全量
/// スナップショットへ倒す（差分の誤配信＝silent corruption より、全量の無駄の方が安い）。
enum TranscriptDeltaCursor {
    /// `"<count>:<hex fnv-1a>"`。count は項目数、hash は先頭 count 項目の内容ハッシュ。
    /// 内容が同一なら同一文字列になる（＝空 delta のポーリングは同一カーソルを返す）。
    static func encode(_ items: [ChatItem]) -> String {
        "\(items.count):\(String(hash(items), radix: 16))"
    }

    static func parse(_ cursor: String) -> (count: Int, hash: UInt64)? {
        let parts = cursor.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let count = Int(parts[0]), count >= 0,
              let hash = UInt64(parts[1], radix: 16)
        else {
            return nil
        }
        return (count, hash)
    }

    /// 決定論的 FNV-1a 64bit。クライアントが観測する同一性（id＋内容、timestamp は除外＝
    /// ChatItem の Equatable と同じ観点）を符号化してハッシュする。
    ///
    /// **各フィールドを長さプレフィックス付きで枠取りする**のが健全性の要。区切り文字方式は、
    /// フィールド値自体が区切り文字を含むとバイト列がフィールド境界を跨いで同一化しうる（例:
    /// command="a", output="b|c" と command="a|b", output="c" が衝突）。長さ枠取りなら各フィールドの
    /// 境界が長さで固定され、内容がどうであれ別フィールドのバイトと混ざらない（衝突不可能）。
    /// 可変長配列（fileChange.changes / userMessage.attachments）は要素数もフィールドとして枠取りし、
    /// arity（要素数）の食い違いも捕捉する。
    static func hash(_ items: [ChatItem]) -> UInt64 {
        var state: UInt64 = 0xcbf2_9ce4_8422_2325
        for item in items {
            for field in contentFields(item) {
                frame(&state, field)
            }
            // 項目終端（フィールド数の違いによる aliasing を防ぐ番兵）
            mix(&state, 0xFE)
        }
        return state
    }

    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    private static func mix(_ state: inout UInt64, _ byte: UInt8) {
        state ^= UInt64(byte)
        state = state &* prime
    }

    /// 1 フィールドを「8バイトのリトルエンディアン長 + 本体バイト列」で枠取りしてハッシュに混ぜる。
    private static func frame(_ state: inout UInt64, _ field: String) {
        var length = UInt64(field.utf8.count)
        for _ in 0..<8 {
            mix(&state, UInt8(length & 0xFF))
            length >>= 8
        }
        for byte in field.utf8 {
            mix(&state, byte)
        }
    }

    /// クライアント観測内容を、順序が意味を持つフィールド列に分解する。ChatItem.Equatable が比較する
    /// id＋内容フィールドを含み、timestamp は含めない（in-place 編集は text/output/message 等の変化で
    /// 必ず捕捉される）。Optional は「値」と「存在フラグ」の2フィールドで nil と空文字を弁別する。
    private static func contentFields(_ item: ChatItem) -> [String] {
        switch item {
        case let .userMessage(id, text, _, attachments):
            var fields = ["u", id, text, String(attachments.count)]
            for attachment in attachments {
                fields.append(attachment.mediaType)
                fields.append(attachment.filename ?? "")
                fields.append(attachment.filename == nil ? "0" : "1")
            }
            return fields
        case let .agentMessage(id, text, _):
            return ["a", id, text]
        case let .reasoning(id, text, _):
            return ["r", id, text]
        case let .commandExecution(id, command, output, _):
            return ["c", id, command ?? "", command == nil ? "0" : "1", output]
        case let .fileChange(id, changes, _):
            var fields = ["f", id, String(changes.count)]
            for change in changes {
                fields.append(change.path)
                fields.append(change.diff)
                fields.append(change.kind ?? "")
                fields.append(change.kind == nil ? "0" : "1")
            }
            return fields
        case let .error(id, message, _):
            return ["e", id, message]
        case let .subAgentMarker(id, subagentType, description, status):
            return ["s", id, subagentType, description, status.rawValue]
        case let .turnCost(id, costUSD, _):
            return ["t", id, String(costUSD)]
        case let .userQuestion(id, requestId, questions, answers, state, _):
            // state/answers の変化で署名が変わり、モバイルの差分ポーリングが更新を拾える。
            var fields = ["q", id, requestId, state.rawValue, String(questions.count)]
            for question in questions {
                fields.append(question.question)
                fields.append(question.header)
                fields.append(question.multiSelect ? "1" : "0")
                fields.append(String(question.options.count))
                for option in question.options {
                    fields.append(option.label)
                    fields.append(option.description ?? "")
                    fields.append(option.description == nil ? "0" : "1")
                }
            }
            if let answers {
                fields.append(String(answers.count))
                for key in answers.keys.sorted() {
                    fields.append(key)
                    fields.append(contentsOf: answers[key] ?? [])
                }
            } else {
                fields.append("nil")
            }
            return fields
        }
    }
}

extension ChatSessionViewModel {
    /// 契約6 の差分エンジン。現在の transcript と `since` カーソルから差分/全量を決める。
    /// - `since == nil`: 全量（`isSnapshot == false`）＋現行カーソル（＝従来 `/messages` ＋cursor）。
    /// - `since` 有効かつ発行以降が append のみ: 新規分のみ（新規なしは空。`isSnapshot == false`）。
    /// - `since` が不正/期限切れ、または prefix に編集/置換/縮小が起きた: 全量（`isSnapshot == true`）。
    ///
    /// 400 は返さない（不正カーソルは全量スナップショットで応答）。カーソルは不透明。
    public func transcriptDelta(since cursor: String?) -> TranscriptDelta {
        let current = transcript
        let currentCursor = TranscriptDeltaCursor.encode(current)

        guard let cursor else {
            // since 省略＝初回取得。全量だがフォールバックではない。
            return TranscriptDelta(items: current, cursor: currentCursor, isSnapshot: false)
        }

        guard let (count, hash) = TranscriptDeltaCursor.parse(cursor),
              count <= current.count,
              TranscriptDeltaCursor.hash(Array(current.prefix(count))) == hash
        else {
            // 不正/期限切れカーソル・縮小・prefix 変化 → 全量スナップショット。
            return TranscriptDelta(items: current, cursor: currentCursor, isSnapshot: true)
        }

        // prefix が発行時と一致＝以降 append のみ。新規分だけを返す（新規なしは空）。
        let newItems = Array(current[count...])
        return TranscriptDelta(items: newItems, cursor: currentCursor, isSnapshot: false)
    }
}
