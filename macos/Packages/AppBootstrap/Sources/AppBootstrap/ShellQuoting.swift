import Foundation

/// sh コマンドへ文字列を安全に埋め込むためのクォートユーティリティ。
public enum ShellQuoting {
    /// 値全体をシングルクォートで囲む。値中のシングルクォートは `'\''` に展開して
    /// クォートを閉じずに連結する（sh 注入の防壁。例: `a'b` → `'a'\''b'`）。
    public static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
