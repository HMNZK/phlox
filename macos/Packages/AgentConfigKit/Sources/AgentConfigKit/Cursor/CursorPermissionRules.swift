import Foundation

/// Cursor の許可ルールのバケット。`permissions.allow` / `.deny` に対応する。
/// Claude Code と違い「毎回たずねる」バケットは無く、許可リスト外の扱いは `approvalMode` が決める。
public enum CursorPermissionBucket: String, Sendable, CaseIterable, Identifiable {
    case allow
    case deny

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .allow: return "許可"
        case .deny: return "拒否"
        }
    }

    public var explanation: String {
        switch self {
        case .allow: return "確認なしで実行してよい操作。"
        case .deny: return "実行させない操作。許可より優先されます。"
        }
    }

    public var symbolName: String {
        switch self {
        case .allow: return "checkmark.shield"
        case .deny: return "hand.raised"
        }
    }
}

/// `permissions` の2バケットだけを取り出した編集用モデル。
/// ここで扱わないキーは `apply(to:)` の書き戻しでそのまま残す。
public struct CursorPermissionRules: Sendable, Equatable {
    public var allow: [String]
    public var deny: [String]

    public init(allow: [String] = [], deny: [String] = []) {
        self.allow = allow
        self.deny = deny
    }

    public subscript(bucket: CursorPermissionBucket) -> [String] {
        get {
            switch bucket {
            case .allow: return allow
            case .deny: return deny
            }
        }
        set {
            switch bucket {
            case .allow: allow = newValue
            case .deny: deny = newValue
            }
        }
    }

    public var isEmpty: Bool { allow.isEmpty && deny.isEmpty }

    public var count: Int { allow.count + deny.count }

    public static func extract(from root: JSONValue) -> CursorPermissionRules {
        let permissions = root["permissions"]
        return CursorPermissionRules(
            allow: permissions?["allow"]?.stringArrayValue ?? [],
            deny: permissions?["deny"]?.stringArrayValue ?? []
        )
    }

    /// 設定ファイル全体へ書き戻す。`permissions` 配下の未知キーは保持する。
    /// Cursor は空配列でもキー自体を持つので、空になっても `[]` を残す（キーを消すと CLI が作り直す）。
    public func apply(to root: JSONValue) -> JSONValue {
        var permissions = root["permissions"]?.objectValue ?? [:]
        for bucket in CursorPermissionBucket.allCases {
            permissions[bucket.rawValue] = .array(self[bucket].map { .string($0) })
        }
        return root.settingTopLevel("permissions", to: .object(permissions))
    }

    @discardableResult
    public mutating func add(_ rule: String, to bucket: CursorPermissionBucket) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !self[bucket].contains(trimmed) else { return false }
        self[bucket].append(trimmed)
        return true
    }

    public mutating func remove(_ rule: String, from bucket: CursorPermissionBucket) {
        self[bucket].removeAll { $0 == rule }
    }

    public mutating func move(_ rule: String, from source: CursorPermissionBucket, to destination: CursorPermissionBucket) {
        guard source != destination else { return }
        remove(rule, from: source)
        add(rule, to: destination)
    }
}
