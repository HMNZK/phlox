import Foundation

/// `~/.cursor/cli-config.json` のうち、画面から触れるようにした設定1項目。
///
/// このファイルには `authInfo`（認証情報）や各種キャッシュも入っている。それらは
/// **画面に出さず、書き込みでも触らない**（部分更新なので自然に温存される）。
public enum CursorSettingKey: String, Sendable, CaseIterable, Identifiable {
    // 動作
    case approvalMode
    case sandboxMode
    case autoAcceptWebSearch
    case rewind
    case modelSlashCommands
    case notifications
    case hints
    // 表示
    case zenMode
    case showLineNumbers
    case showThinkingBlocks
    case showStatusIndicators
    case showStatusLineRunningTime
    case vimMode
    // Git
    case attributeCommitsToAgent
    case attributePRsToAgent

    public var id: String { rawValue }

    public enum Kind: Sendable, Equatable {
        case toggle
        case choice([String])
    }

    public enum Group: String, Sendable, CaseIterable, Identifiable {
        case behavior
        case display
        case git

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .behavior: return "動作"
            case .display: return "表示"
            case .git: return "Git"
            }
        }

        public var symbolName: String {
            switch self {
            case .behavior: return "slider.horizontal.3"
            case .display: return "eye"
            case .git: return "arrow.triangle.branch"
            }
        }
    }

    /// cli-config.json 内の位置。
    public var path: [String] {
        switch self {
        case .approvalMode: return ["approvalMode"]
        case .sandboxMode: return ["sandbox", "mode"]
        case .autoAcceptWebSearch: return ["autoAcceptWebSearch"]
        case .rewind: return ["rewind"]
        case .modelSlashCommands: return ["modelSlashCommands"]
        case .notifications: return ["notifications"]
        case .hints: return ["hints"]
        case .zenMode: return ["display", "zenMode"]
        case .showLineNumbers: return ["display", "showLineNumbers"]
        case .showThinkingBlocks: return ["display", "showThinkingBlocks"]
        case .showStatusIndicators: return ["display", "showStatusIndicators"]
        case .showStatusLineRunningTime: return ["display", "showStatusLineRunningTime"]
        case .vimMode: return ["editor", "vimMode"]
        case .attributeCommitsToAgent: return ["attribution", "attributeCommitsToAgent"]
        case .attributePRsToAgent: return ["attribution", "attributePRsToAgent"]
        }
    }

    public var group: Group {
        switch self {
        case .approvalMode, .sandboxMode, .autoAcceptWebSearch, .rewind,
             .modelSlashCommands, .notifications, .hints:
            return .behavior
        case .zenMode, .showLineNumbers, .showThinkingBlocks,
             .showStatusIndicators, .showStatusLineRunningTime, .vimMode:
            return .display
        case .attributeCommitsToAgent, .attributePRsToAgent:
            return .git
        }
    }

    public var kind: Kind {
        switch self {
        case .approvalMode: return .choice(["allowlist", "unrestricted", "auto-review"])
        case .sandboxMode: return .choice(["disabled", "enabled"])
        default: return .toggle
        }
    }

    public var displayName: String {
        switch self {
        case .approvalMode: return "承認の求め方"
        case .sandboxMode: return "サンドボックス"
        case .autoAcceptWebSearch: return "Web 検索を自動で許可"
        case .rewind: return "巻き戻しを使う"
        case .modelSlashCommands: return "スラッシュコマンドでモデルを切り替える"
        case .notifications: return "通知"
        case .hints: return "ヒント表示"
        case .zenMode: return "集中モード"
        case .showLineNumbers: return "行番号を出す"
        case .showThinkingBlocks: return "思考ブロックを出す"
        case .showStatusIndicators: return "状態インジケータを出す"
        case .showStatusLineRunningTime: return "経過時間を出す"
        case .vimMode: return "Vim キーバインド"
        case .attributeCommitsToAgent: return "コミットをエージェント名義にする"
        case .attributePRsToAgent: return "PR をエージェント名義にする"
        }
    }

    public var explanation: String? {
        switch self {
        case .approvalMode:
            return "allowlist は許可リスト外で確認、unrestricted は全部そのまま実行、auto-review はサーバー側の判定に任せます。"
        case .sandboxMode:
            return "有効にするとコマンドをサンドボックス内で実行します。"
        default:
            return nil
        }
    }

    /// 画面の選択肢。現在値が既知の並びに無ければ、それも選択肢として残す。
    public func options(current: String?) -> [String] {
        guard case .choice(let values) = kind else { return [] }
        guard let current, !current.isEmpty, !values.contains(current) else { return values }
        return [current] + values
    }
}

/// cli-config.json の設定値の読み書き。
public enum CursorGeneralSettings {
    public static func keys(in group: CursorSettingKey.Group) -> [CursorSettingKey] {
        CursorSettingKey.allCases.filter { $0.group == group }
    }

    public static func bool(_ key: CursorSettingKey, in root: JSONValue) -> Bool? {
        root.value(at: key.path)?.boolValue
    }

    public static func string(_ key: CursorSettingKey, in root: JSONValue) -> String? {
        root.value(at: key.path)?.stringValue
    }

    public static func setBool(_ value: Bool, for key: CursorSettingKey, in root: JSONValue) -> JSONValue {
        root.setting(key.path, to: .bool(value))
    }

    public static func setString(_ value: String, for key: CursorSettingKey, in root: JSONValue) -> JSONValue {
        root.setting(key.path, to: .string(value))
    }
}
