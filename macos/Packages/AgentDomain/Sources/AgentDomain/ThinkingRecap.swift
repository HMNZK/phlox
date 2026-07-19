import Foundation

/// 実行中ターンのツール活動（recap 要約用）。
public enum RecapActivity: Equatable, Sendable {
    case reading(String)
    case running(String)
    case editing(String)

    private static let readCommandNames: Set<String> = [
        "cat", "less", "head", "tail", "grep", "rg", "find", "ls",
        "bat", "fd", "cd", "pwd", "echo", "which", "stat", "wc",
    ]

    /// コマンド文字列を read/run に分類する（先頭トークンの basename で判定）。
    public static func fromCommand(_ command: String?) -> RecapActivity {
        guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running("コマンド")
        }
        let firstToken = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let base = basename(firstToken)
        if readCommandNames.contains(base) {
            return .reading(command)
        }
        return .running(command)
    }

    private static func basename(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

/// 実行中ターンの「いま何をしているか」要約コア（純粋関数）。
public enum ThinkingRecap {
    public static let defaultThreshold: TimeInterval = 5

    /// 実行中ターンの recap 要約。
    /// - elapsed < threshold → nil
    /// - recentActivity.last があればその活動ラベルを優先
    /// - 無ければ reasoningText からヒューリスティック抽出
    /// - どちらも空 → nil
    public static func summary(
        reasoningText: String?,
        recentActivity: [RecapActivity],
        elapsed: TimeInterval,
        threshold: TimeInterval = defaultThreshold
    ) -> String? {
        guard elapsed >= threshold else { return nil }

        if let activity = recentActivity.last {
            return clamp(label(for: activity))
        }

        guard let extracted = extract(from: reasoningText) else { return nil }
        let result = clamp(extracted)
        return result.isEmpty ? nil : result
    }

    private static func label(for activity: RecapActivity) -> String {
        switch activity {
        case .reading(let x): return "\(x) を読み込み中"
        case .running(let x): return "\(x) を実行中"
        case .editing(let x): return "\(x) を編集中"
        }
    }

    /// 末尾側の見出し（`#`/`##`/`###`）を優先。無ければ末尾の非空白行。全体が空白のみなら nil。
    private static func extract(from reasoningText: String?) -> String? {
        guard let reasoningText else { return nil }

        let lines = reasoningText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        for line in lines.reversed() {
            if let heading = headingText(line) {
                return heading
            }
        }
        return lines.last
    }

    /// `#` / `##` / `###` のみ見出し。`####` 以上は非見出し。
    private static func headingText(_ line: String) -> String? {
        var hashCount = 0
        for ch in line {
            if ch == "#" {
                hashCount += 1
                if hashCount > 3 { return nil }
            } else {
                break
            }
        }
        guard hashCount >= 1 else { return nil }
        return String(line.dropFirst(hashCount)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 最大 60 文字。超過は prefix(60)+"…"。ラベルの意図的な空白は落とさない。
    private static func clamp(_ text: String) -> String {
        guard text.count > 60 else { return text }
        return String(text.prefix(60)) + "…"
    }
}
