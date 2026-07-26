import Foundation

/// 出力スタイル（`settings.json` の `outputStyle`）の選択肢。
///
/// 組み込みに加えて `~/.claude/output-styles/*.md` に置かれたカスタムスタイルも選べる。
public struct ClaudeOutputStyleOption: Sendable, Equatable, Identifiable, Hashable {
    /// 設定ファイルへ書く値。既定（未設定）は `nil`。
    public let value: String?
    public let displayName: String
    public let detail: String

    public var id: String { value ?? "__default__" }

    public init(value: String?, displayName: String, detail: String) {
        self.value = value
        self.displayName = displayName
        self.detail = detail
    }

    public static let builtins: [ClaudeOutputStyleOption] = [
        ClaudeOutputStyleOption(
            value: nil,
            displayName: "既定",
            detail: "Claude Code の標準の応答スタイル。"
        ),
        ClaudeOutputStyleOption(
            value: "Explanatory",
            displayName: "Explanatory",
            detail: "実装の合間に、なぜそうするかの解説を挟む。"
        ),
        ClaudeOutputStyleOption(
            value: "Learning",
            displayName: "Learning",
            detail: "手を動かして学ぶ前提で、要所を自分で書かせる。"
        ),
    ]
}

public enum ClaudeOutputStyleSettings {
    public static func extract(from root: JSONValue) -> String? {
        guard let value = root["outputStyle"]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    /// 書き戻す。`nil`（既定）ならキーごと消す。
    public static func apply(_ style: String?, to root: JSONValue) -> JSONValue {
        guard let style, !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return root.settingTopLevel("outputStyle", to: nil)
        }
        return root.settingTopLevel("outputStyle", to: .string(style))
    }

    /// 組み込み＋`~/.claude/output-styles/*.md` のカスタムスタイルを合わせた選択肢を返す。
    public static func availableOptions(
        paths: ClaudeConfigPaths,
        fileManager: FileManager = .default
    ) -> [ClaudeOutputStyleOption] {
        var options = ClaudeOutputStyleOption.builtins
        let directory = paths.claudeDirectory.appendingPathComponent("output-styles", isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".md") {
            let style = String(name.dropLast(3))
            guard !options.contains(where: { $0.value == style }) else { continue }
            options.append(
                ClaudeOutputStyleOption(
                    value: style,
                    displayName: style,
                    detail: "~/.claude/output-styles/\(name)"
                )
            )
        }
        return options
    }
}
