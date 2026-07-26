import Foundation

/// 許可ルールのバケット。Claude Code の `permissions.allow` / `.deny` / `.ask` に対応する。
public enum ClaudePermissionBucket: String, Sendable, CaseIterable, Identifiable {
    case allow
    case ask
    case deny

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allow: return "許可"
        case .ask: return "確認する"
        case .deny: return "拒否"
        }
    }

    public var explanation: String {
        switch self {
        case .allow: return "確認なしで実行してよい操作。"
        case .ask: return "実行前に毎回たずねる操作。"
        case .deny: return "実行させない操作。allow より優先されます。"
        }
    }

    public var symbolName: String {
        switch self {
        case .allow: return "checkmark.shield"
        case .ask: return "questionmark.circle"
        case .deny: return "hand.raised"
        }
    }
}

/// `permissions` の3バケットだけを取り出した編集用モデル。
///
/// `defaultMode` や `additionalDirectories` など、ここで扱わないキーは
/// `apply(to:)` で元のオブジェクトへ書き戻すときにそのまま残す。
public struct ClaudePermissionRules: Sendable, Equatable {
    public var allow: [String]
    public var ask: [String]
    public var deny: [String]

    public init(allow: [String] = [], ask: [String] = [], deny: [String] = []) {
        self.allow = allow
        self.ask = ask
        self.deny = deny
    }

    public subscript(bucket: ClaudePermissionBucket) -> [String] {
        get {
            switch bucket {
            case .allow: return allow
            case .ask: return ask
            case .deny: return deny
            }
        }
        set {
            switch bucket {
            case .allow: allow = newValue
            case .ask: ask = newValue
            case .deny: deny = newValue
            }
        }
    }

    public var isEmpty: Bool { allow.isEmpty && ask.isEmpty && deny.isEmpty }

    /// 設定ファイル全体から `permissions` を読む。
    public static func extract(from root: JSONValue) -> ClaudePermissionRules {
        let permissions = root["permissions"]
        return ClaudePermissionRules(
            allow: permissions?["allow"]?.stringArrayValue ?? [],
            ask: permissions?["ask"]?.stringArrayValue ?? [],
            deny: permissions?["deny"]?.stringArrayValue ?? []
        )
    }

    /// 設定ファイル全体へ書き戻す。`permissions` 配下の未知キーは保持する。
    /// バケットが空になったらそのキー自体を消し、3つとも空かつ他キーも無ければ `permissions` ごと消す。
    public func apply(to root: JSONValue) -> JSONValue {
        var permissions = root["permissions"]?.objectValue ?? [:]
        for bucket in ClaudePermissionBucket.allCases {
            let rules = self[bucket]
            if rules.isEmpty {
                permissions.removeValue(forKey: bucket.rawValue)
            } else {
                permissions[bucket.rawValue] = .array(rules.map { .string($0) })
            }
        }
        return root.settingTopLevel("permissions", to: permissions.isEmpty ? nil : .object(permissions))
    }

    /// ルールを追加する。前後の空白は落とし、空文字と重複は入れない。追加できたら true。
    @discardableResult
    public mutating func add(_ rule: String, to bucket: ClaudePermissionBucket) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !self[bucket].contains(trimmed) else { return false }
        self[bucket].append(trimmed)
        return true
    }

    public mutating func remove(_ rule: String, from bucket: ClaudePermissionBucket) {
        self[bucket].removeAll { $0 == rule }
    }

    /// ルールを別のバケットへ移す（allow → deny など）。
    public mutating func move(_ rule: String, from source: ClaudePermissionBucket, to destination: ClaudePermissionBucket) {
        guard source != destination else { return }
        remove(rule, from: source)
        add(rule, to: destination)
    }
}
