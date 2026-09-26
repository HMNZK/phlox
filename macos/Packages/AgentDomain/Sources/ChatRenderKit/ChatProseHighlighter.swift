import Foundation

/// 会話の本文で強調する部分の種類（Chat Screen.dc.html の `rich()`）。
public enum ChatProseSpanKind: Equatable, Sendable {
    /// `expiresAt`・`ChatApprovalRequest` のようなコード上の名前。
    case identifier
    /// `ApprovalBrokerTests.swift` のようなファイル名。
    case file
    /// `.expired` のような `.` で始まる名前。
    case member
    /// 「成功」「+3」。
    case success
    /// 「失敗」「−2」。
    case failure
    /// 「3 件」「10 分」のような数量。
    case quantity
}

public struct ChatProseSpan: Equatable, Sendable {
    public let range: Range<String.Index>
    public let kind: ChatProseSpanKind
}

public enum ChatProseHighlighter {
    // ponytail: 見本の正規表現をそのまま移した経験則。英字の前後は「英数字でない」で区切る（日本語に接していても拾う）。
    private static let extensions = "swift|md|png|json|xcstrings|ts|tsx|js|jsx|py|go|rs|rb|java|kt|c|h|m|cpp|sh|yml|yaml|toml|txt|html|css|plist"
    private static let rules: [(String, ChatProseSpanKind)] = [
        ("(?<![A-Za-z0-9_])[A-Za-z0-9_/.-]+\\.(?:\(extensions))(?![A-Za-z0-9_])", .file),
        ("(?<![A-Za-z0-9_])[a-z]+[A-Z][A-Za-z0-9_]*(?:\\(\\))?(?![A-Za-z0-9_])", .identifier),
        ("(?<![A-Za-z0-9_])[A-Z][a-z]+[A-Z][A-Za-z0-9_]*(?![A-Za-z0-9_])", .identifier),
        ("(?<![A-Za-z0-9_])\\.[a-z]+(?=[\\s、。）)]|$)", .member),
        ("\\+\\d+|すべて成功|成功", .success),
        ("−\\d+|失敗", .failure),
        ("\\d+(?:\\.\\d+)?\\s?(?:件|分|秒|行)", .quantity),
    ]
    private static let pattern = try! NSRegularExpression(pattern: rules.map { "(\($0.0))" }.joined(separator: "|"))

    public static func spans(in text: String) -> [ChatProseSpan] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let group = rules.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }),
                  let range = Range(match.range, in: text) else { return nil }
            return ChatProseSpan(range: range, kind: rules[group].1)
        }
    }
}
