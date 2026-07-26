import Foundation

/// `config.toml` のトップレベルにある「よく変える設定」の1項目。
///
/// 取りうる値は Codex CLI 0.144 の実装から採った固定の並び。ファイルに入っている値が
/// この並びに無い場合でも、`options(current:)` がその値を先頭に足して**選択肢から消えないようにする**
/// （知らない値を勝手に既定値へ倒して書き潰さないため）。
public enum CodexSettingKey: String, Sendable, CaseIterable, Identifiable {
    case model
    case modelReasoningEffort = "model_reasoning_effort"
    case personality
    case approvalPolicy = "approval_policy"
    case sandboxMode = "sandbox_mode"
    case serviceTier = "service_tier"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .model: return "モデル"
        case .modelReasoningEffort: return "思考の深さ"
        case .personality: return "応答の人格"
        case .approvalPolicy: return "承認の求め方"
        case .sandboxMode: return "サンドボックス"
        case .serviceTier: return "サービスティア"
        }
    }

    public var explanation: String {
        switch self {
        case .model: return "既定で使うモデル。"
        case .modelReasoningEffort: return "1ターンにかける推論量。深いほど遅く高価になります。"
        case .personality: return "応答の口調。"
        case .approvalPolicy: return "コマンド実行前にどこまで確認を求めるか。"
        case .sandboxMode: return "モデルが実行するコマンドに与える権限の広さ。"
        case .serviceTier: return "API のサービスティア。"
        }
    }

    /// 選択肢が決まっているキーか（model は自由入力）。
    public var isEnumerated: Bool { !knownValues.isEmpty }

    /// Codex CLI が受け付ける値。
    public var knownValues: [String] {
        switch self {
        case .model:
            return []
        case .modelReasoningEffort:
            return ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
        case .personality:
            return ["friendly", "pragmatic"]
        case .approvalPolicy:
            return ["untrusted", "on-request", "granular", "never"]
        case .sandboxMode:
            return ["read-only", "workspace-write", "danger-full-access"]
        case .serviceTier:
            return ["default", "flex", "priority"]
        }
    }

    /// 画面の選択肢。現在値が既知の並びに無ければ、それも選択肢として残す。
    public func options(current: String?) -> [String] {
        guard let current, !current.isEmpty, !knownValues.contains(current) else { return knownValues }
        return [current] + knownValues
    }
}

/// `config.toml` のトップレベル設定の読み書き。
public enum CodexGeneralSettings {
    /// 画面で扱うキーの並び。
    public static let editableKeys: [CodexSettingKey] = CodexSettingKey.allCases

    public static func value(_ key: CodexSettingKey, in document: TOMLDocument) -> String? {
        document.string(at: [key.rawValue])
    }

    /// 値を設定する。空文字ならキーごと消す（＝Codex の既定に戻す）。
    public static func setValue(_ value: String?, for key: CodexSettingKey, in document: inout TOMLDocument) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            document.removeKey(at: [key.rawValue])
        } else {
            document.setString(trimmed, at: [key.rawValue])
        }
    }

    /// 現在値をまとめて読む。
    public static func snapshot(from document: TOMLDocument) -> [CodexSettingKey: String] {
        var result: [CodexSettingKey: String] = [:]
        for key in editableKeys {
            if let value = value(key, in: document) { result[key] = value }
        }
        return result
    }
}
