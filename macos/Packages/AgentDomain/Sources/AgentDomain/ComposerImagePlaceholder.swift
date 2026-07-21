import Foundation

// task-1 契約の PM スタブ。API 表面は受け入れテスト
// ComposerImagePlaceholderAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-1.md
//
// macOS アプリ（SessionFeature）と iOS アプリ（PhloxKit）の双方が参照する共有面。
// 「本文へ埋め込む画像プレースホルダ」の表記と挿入・削除の規則をここ1箇所で決める。

/// 本文テキストに埋め込む画像プレースホルダ（`[Image #1]`）の生成・挿入・削除。
/// すべて純関数（グローバル状態・日時・乱数に依存しない）。
public enum ComposerImagePlaceholder {
    /// 番号 `number` のプレースホルダ文字列。
    public static func text(for number: Int) -> String {
        ""
    }

    /// 既存の番号列から次に振る番号を決める。欠番は詰めない。
    public static func nextNumber(after existingNumbers: [Int]) -> Int {
        0
    }

    /// `cursorUTF16` の位置にプレースホルダを挿入し、挿入後のテキストとカーソル位置を返す。
    public static func inserting(
        number: Int,
        into text: String,
        cursorUTF16: Int
    ) -> (text: String, cursorUTF16: Int) {
        (text, cursorUTF16)
    }

    /// 本文から番号 `number` のプレースホルダを1つ取り除く。
    public static func removing(number: Int, from text: String) -> String {
        text
    }
}
