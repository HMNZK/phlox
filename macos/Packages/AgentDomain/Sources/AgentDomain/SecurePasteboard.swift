#if canImport(AppKit)
import AppKit
import Foundation

/// 機密文字列（トークン等）を NSPasteboard へ安全側の既定でコピーするヘルパー。
///
/// - `org.nspasteboard.ConcealedType` を併記し、クリップボード履歴・Universal Clipboard 系の
///   ツールへ「機密であり保存すべきでない」ことを通知する（nspasteboard.org 規約）。
/// - changeCount 照合付きの自動クリアで、コピーしたまま放置されたトークンの滞留を防ぐ。
///   照合により、ユーザーがその後に自分でコピーした無関係な内容は消さない。
public enum SecurePasteboard {
    /// nspasteboard.org 規約の隠匿マーカー型。
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// value を `.string` と `concealedType` の両タイプで書き込み、書き込み後の changeCount を返す。
    @discardableResult
    public static func copyConcealed(_ value: String, to pasteboard: NSPasteboard = .general) -> Int {
        // declareTypes と後続の setString は同一 changeCount サイクル内で行う
        // （別途 clearContents を挟むと changeCount がずれ、照合クリアが壊れるため）。
        pasteboard.declareTypes([.string, concealedType], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setString(value, forType: concealedType)
        return pasteboard.changeCount
    }

    /// changeCount が expectedChangeCount と一致する（＝コピー後に誰も上書きしていない）場合のみ
    /// 中身を消去して true を返す。上書きされていた場合は何もせず false を返す。
    @discardableResult
    public static func clearIfUnchanged(
        _ pasteboard: NSPasteboard = .general,
        expectedChangeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        pasteboard.clearContents()
        return true
    }

    /// seconds 秒後に `clearIfUnchanged` を実行する自動クリアを予約する。
    public static func scheduleAutoClear(
        after seconds: TimeInterval,
        pasteboard: NSPasteboard = .general,
        expectedChangeCount: Int
    ) {
        // NSPasteboard は Sendable 適合ではないが、クラス自体はシングルトン/共有インスタンスの
        // 単純なプロパティ読み書きのみで使う既存の慣行に倣い、意図的にキャプチャする。
        nonisolated(unsafe) let target = pasteboard
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            clearIfUnchanged(target, expectedChangeCount: expectedChangeCount)
        }
    }
}
#endif
