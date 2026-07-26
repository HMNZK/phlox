import Foundation

/// `settings.json` の `statusLine`。Claude Code のステータス行を外部コマンドで描くための設定。
public struct ClaudeStatusLineSettings: Sendable, Equatable {
    public var isEnabled: Bool
    public var command: String
    /// 左右の余白。Claude Code の既定は 0 で、`nil` は「指定なし（既定に従う）」。
    public var padding: Int?

    public init(isEnabled: Bool = false, command: String = "", padding: Int? = nil) {
        self.isEnabled = isEnabled
        self.command = command
        self.padding = padding
    }

    public static func extract(from root: JSONValue) -> ClaudeStatusLineSettings {
        guard let statusLine = root["statusLine"]?.objectValue else {
            return ClaudeStatusLineSettings()
        }
        let command = statusLine["command"]?.stringValue ?? ""
        return ClaudeStatusLineSettings(
            isEnabled: !command.isEmpty,
            command: command,
            padding: statusLine["padding"]?.intValue
        )
    }

    /// 書き戻す。無効・コマンド未入力なら `statusLine` ごと消す（空のオブジェクトを残さない）。
    /// `statusLine` 配下の未知キーは保持する。
    public func apply(to root: JSONValue) -> JSONValue {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else {
            return root.settingTopLevel("statusLine", to: nil)
        }
        var statusLine = root["statusLine"]?.objectValue ?? [:]
        statusLine["type"] = .string("command")
        statusLine["command"] = .string(trimmed)
        if let padding {
            statusLine["padding"] = .int(padding)
        } else {
            statusLine.removeValue(forKey: "padding")
        }
        return root.settingTopLevel("statusLine", to: .object(statusLine))
    }
}
