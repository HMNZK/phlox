import Foundation

/// `settings.json` の `hooks` に登録された1コマンド。
///
/// 実体は `hooks.<イベント>[groupIndex].hooks[hookIndex]`。位置で同定するので、
/// 一覧を取り直さずに続けて複数削除しない（削除のたびに読み直すこと）。
public struct ClaudeHookEntry: Sendable, Equatable, Identifiable {
    public let event: String
    public let groupIndex: Int
    public let hookIndex: Int
    /// `matcher`（対象ツール名のパターン）。イベントによっては存在しない。
    public let matcher: String?
    public let type: String
    public let command: String
    public let timeoutSeconds: Int?

    public var id: String { "\(event)#\(groupIndex)#\(hookIndex)" }

    public init(
        event: String,
        groupIndex: Int,
        hookIndex: Int,
        matcher: String?,
        type: String,
        command: String,
        timeoutSeconds: Int?
    ) {
        self.event = event
        self.groupIndex = groupIndex
        self.hookIndex = hookIndex
        self.matcher = matcher
        self.type = type
        self.command = command
        self.timeoutSeconds = timeoutSeconds
    }
}

/// `hooks` セクションの読み取り・編集（純関数）。
///
/// 設定ファイルは手書きされうるので、**自分が知らないキーは触らない**。
/// エントリの追加・削除は配列の要素を足し引きするだけで、他の要素はそのまま持ち回る。
public enum ClaudeHookSettings {
    /// Claude Code が定義しているフックイベント。ファイル側にこれ以外の名前があっても読み飛ばさない。
    public static let knownEvents = [
        "PreToolUse",
        "PostToolUse",
        "UserPromptSubmit",
        "Notification",
        "Stop",
        "SubagentStop",
        "PreCompact",
        "SessionStart",
        "SessionEnd",
    ]

    /// 登録済みフックを、イベント名の昇順・ファイル内の出現順で返す。
    public static func entries(from root: JSONValue) -> [ClaudeHookEntry] {
        guard let hooks = root["hooks"]?.objectValue else { return [] }
        var result: [ClaudeHookEntry] = []
        for event in hooks.keys.sorted() {
            guard let groups = hooks[event]?.arrayValue else { continue }
            for (groupIndex, group) in groups.enumerated() {
                let matcher = group["matcher"]?.stringValue
                guard let commands = group["hooks"]?.arrayValue else { continue }
                for (hookIndex, hook) in commands.enumerated() {
                    guard let command = hook["command"]?.stringValue else { continue }
                    result.append(
                        ClaudeHookEntry(
                            event: event,
                            groupIndex: groupIndex,
                            hookIndex: hookIndex,
                            matcher: matcher,
                            type: hook["type"]?.stringValue ?? "command",
                            command: command,
                            timeoutSeconds: hook["timeout"]?.intValue
                        )
                    )
                }
            }
        }
        return result
    }

    /// 1エントリを取り除く。取り除いた結果、空になったグループ・イベント・`hooks` 自体も畳む。
    public static func removing(_ entry: ClaudeHookEntry, from root: JSONValue) -> JSONValue {
        guard var hooks = root["hooks"]?.objectValue,
              var groups = hooks[entry.event]?.arrayValue,
              groups.indices.contains(entry.groupIndex),
              var group = groups[entry.groupIndex].objectValue,
              var commands = group["hooks"]?.arrayValue,
              commands.indices.contains(entry.hookIndex)
        else { return root }

        commands.remove(at: entry.hookIndex)
        if commands.isEmpty {
            groups.remove(at: entry.groupIndex)
        } else {
            group["hooks"] = .array(commands)
            groups[entry.groupIndex] = .object(group)
        }

        if groups.isEmpty {
            hooks.removeValue(forKey: entry.event)
        } else {
            hooks[entry.event] = .array(groups)
        }
        return root.settingTopLevel("hooks", to: hooks.isEmpty ? nil : .object(hooks))
    }

    /// フックを1つ足す。同じ `matcher` のグループがあればそこへ追加し、無ければグループを作る。
    /// `matcher` が nil のイベント（Stop 等）は「matcher キーを持たないグループ」を対象にする。
    public static func adding(
        event: String,
        matcher: String?,
        command: String,
        timeoutSeconds: Int?,
        to root: JSONValue
    ) -> JSONValue {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return root }
        let normalizedMatcher = matcher?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMatcher = (normalizedMatcher?.isEmpty ?? true) ? nil : normalizedMatcher

        var hook: [String: JSONValue] = ["type": .string("command"), "command": .string(trimmedCommand)]
        if let timeoutSeconds { hook["timeout"] = .int(timeoutSeconds) }

        var hooks = root["hooks"]?.objectValue ?? [:]
        var groups = hooks[event]?.arrayValue ?? []

        let targetIndex = groups.firstIndex { $0["matcher"]?.stringValue == effectiveMatcher }
        if let targetIndex, var group = groups[targetIndex].objectValue {
            var commands = group["hooks"]?.arrayValue ?? []
            commands.append(.object(hook))
            group["hooks"] = .array(commands)
            groups[targetIndex] = .object(group)
        } else {
            var group: [String: JSONValue] = ["hooks": .array([.object(hook)])]
            if let effectiveMatcher { group["matcher"] = .string(effectiveMatcher) }
            groups.append(.object(group))
        }

        hooks[event] = .array(groups)
        return root.settingTopLevel("hooks", to: .object(hooks))
    }
}
