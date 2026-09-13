/// UX-10b 権限説明の正本。引数のエージェント・設定種類・内部値・言語コードだけで結果が決まり、I/O を持たない。
extension UIWording {
    public enum PermissionAgent: String, CaseIterable, Equatable, Hashable, Sendable {
        case claude
        case codex
        case cursor
        case custom
    }

    public enum PermissionKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case claudePermissionMode
        case codexApprovalPolicy
        case codexSandboxMode
        case codexProfile
        case cursorApprovalMode
        case cursorSandboxMode
        case cursorOperationMode
        case claudeRuleBucket
        case cursorRuleBucket
        case settingKeyTitle
        case permissionsPaneIntro
    }

    public struct PermissionWording: Equatable, Hashable, Sendable {
        public let title: String
        public let explanation: String
    }

    public struct LaunchPermissionWording: Equatable, Hashable, Sendable {
        public let rowLabel: String
        public let offExplanation: String
        public let onExplanation: String
    }

    public static func permission(
        agent: PermissionAgent,
        kind: PermissionKind,
        value: String?,
        languageCode: String
    ) -> PermissionWording {
        let english = permissionUsesEnglish(languageCode)
        return switch (agent, kind) {
        case (.claude, .claudePermissionMode):
            claudePermissionMode(value, english: english)
        case (.codex, .codexApprovalPolicy):
            codexApprovalPolicy(value, english: english)
        case (.codex, .codexSandboxMode):
            codexSandboxMode(value, english: english)
        case (.codex, .codexProfile):
            codexProfile(value, english: english)
        case (.cursor, .cursorApprovalMode):
            cursorApprovalMode(value, english: english)
        case (.cursor, .cursorSandboxMode):
            cursorSandboxMode(value, english: english)
        case (.cursor, .cursorOperationMode):
            cursorOperationMode(value, english: english)
        case (.claude, .claudeRuleBucket):
            claudeRuleBucket(value, english: english)
        case (.cursor, .cursorRuleBucket):
            cursorRuleBucket(value, english: english)
        case (.codex, .settingKeyTitle):
            codexSettingKeyTitle(value, english: english)
        case (.cursor, .settingKeyTitle):
            cursorSettingKeyTitle(value, english: english)
        case (.claude, .permissionsPaneIntro):
            claudePermissionsIntro(english: english)
        case (.cursor, .permissionsPaneIntro):
            cursorPermissionsIntro(english: english)
        default:
            unknown(value, english: english)
        }
    }

    public static func launchPermission(
        agent: PermissionAgent,
        displayName: String,
        languageCode: String
    ) -> LaunchPermissionWording {
        let english = permissionUsesEnglish(languageCode)
        return switch agent {
        case .claude:
            LaunchPermissionWording(
                rowLabel: english ? "Claude Code: Skip approval prompts" : "Claude Code: 承認確認を省略",
                offExplanation: english
                    ? "Specifies auto (automatic judgment) at the next launch."
                    : "次回開始時に自動判定（auto）を指定します。",
                onExplanation: english
                    ? "Specifies bypassPermissions (skip approval prompts) at the next launch. This does not disable the sandbox."
                    : "次回開始時に承認確認の省略（bypassPermissions）を指定します。サンドボックスの解除を意味しません。"
            )
        case .codex:
            LaunchPermissionWording(
                rowLabel: english ? "Codex: Lift approval and execution limits" : "Codex: 承認と実行制限を解除",
                offExplanation: english
                    ? "Specifies on-request and workspace-write in chat. Terminal launches omit the lift arguments and follow Codex settings."
                    : "チャットでは on-request と workspace-write を指定します。ターミナルでは解除引数を付けず、Codex の設定に従います。",
                onExplanation: english
                    ? "Specifies never and danger-full-access in chat. Terminal launches add arguments that lift approval and the sandbox."
                    : "チャットでは never と danger-full-access を指定します。ターミナルでは承認とサンドボックスの解除引数を付けます。"
            )
        case .cursor:
            LaunchPermissionWording(
                rowLabel: english ? "Cursor: Lift approval and execution limits" : "Cursor: 承認と実行制限を解除",
                offExplanation: english
                    ? "Specifies --auto-review and --sandbox enabled at the next launch."
                    : "次回開始時に --auto-review と --sandbox enabled を指定します。",
                onExplanation: english
                    ? "Specifies --force and --sandbox disabled at the next launch."
                    : "次回開始時に --force と --sandbox disabled を指定します。"
            )
        case .custom:
            LaunchPermissionWording(
                rowLabel: english
                    ? "\(displayName): Launch permission settings"
                    : "\(displayName): 起動時の権限設定",
                offExplanation: english
                    ? "Follows this agent's launch settings. Check the agent settings for the allowed scope."
                    : "このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。",
                onExplanation: english
                    ? "Follows this agent's launch settings. Check the agent settings for the allowed scope."
                    : "このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。"
            )
        }
    }

    public static func settingsPermissionFooter(languageCode: String) -> String {
        if permissionUsesEnglish(languageCode) {
            "Changes take effect from the next session start. Approval method and execution limits differ by agent. Enable lift only on projects you trust."
        } else {
            "変更は次回セッション開始から反映されます。承認方式と実行制限はエージェントごとに異なります。解除は信頼できるプロジェクトでのみ有効にしてください。"
        }
    }

    // MARK: - Language (task-48 と同じ規則)

    private static func permissionUsesEnglish(_ languageCode: String) -> Bool {
        permissionPrimaryLanguage(languageCode) == "en"
    }

    private static func permissionPrimaryLanguage(_ languageCode: String) -> String {
        let first = languageCode.split { $0 == "-" || $0 == "_" }.first.map(String.init) ?? ""
        return first.lowercased()
    }

    // MARK: - Fallbacks

    private static func unknown(_ value: String?, english: Bool) -> PermissionWording {
        PermissionWording(
            title: value ?? "",
            explanation: english
                ? "Details of this setting value are unconfirmed. Check the agent settings."
                : "この設定値の詳細は未確認です。エージェントの設定を確認してください。"
        )
    }

    private static func unset(english: Bool) -> PermissionWording {
        PermissionWording(
            title: english ? "Default (unset)" : "既定（未設定）",
            explanation: english
                ? "The value is unset. Check the agent settings for the applied default."
                : "値は未設定です。適用される既定値はエージェントの設定を確認してください。"
        )
    }

    private static func pair(_ titleJA: String, _ titleEN: String, _ explanationJA: String, _ explanationEN: String, english: Bool) -> PermissionWording {
        PermissionWording(
            title: english ? titleEN : titleJA,
            explanation: english ? explanationEN : explanationJA
        )
    }

    // MARK: - Tables

    private static func claudePermissionMode(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case "default", "manual":
            pair(
                "手動承認",
                "Manual",
                "読み取り以外は権限ルールに従って承認を求めます。実行範囲の制限とは別の設定です。",
                "Asks for approval according to permission rules except for reads. This is separate from execution-scope limits.",
                english: english
            )
        case "acceptEdits":
            pair(
                "編集を自動承認",
                "Accept Edits",
                "ファイル編集などを自動承認します。すべてのコマンド実行を承認する設定ではありません。",
                "Automatically approves file edits and similar actions. This does not approve every command.",
                english: english
            )
        case "auto":
            pair(
                "自動判定",
                "Auto",
                "Claude Code が操作を判定します。すべての操作を無条件に許可する設定ではありません。",
                "Claude Code decides how to handle each action. This does not unconditionally allow every action.",
                english: english
            )
        case "bypassPermissions":
            pair(
                "承認確認を省略",
                "Bypass",
                "通常の承認確認を省略します。サンドボックスの解除を意味する設定ではありません。",
                "Skips the usual approval prompts. This does not disable the sandbox.",
                english: english
            )
        case "dontAsk":
            pair(
                "承認が必要な操作を拒否",
                "Don't Ask",
                "事前に許可された操作などを実行し、承認が必要な操作は確認せず拒否します。",
                "Runs previously allowed actions and rejects actions that would need approval, without asking.",
                english: english
            )
        case "plan":
            pair(
                "計画",
                "Plan",
                "調査と計画を行うモードです。編集を進めるモードとは区別されます。",
                "A mode for research and planning. It is distinct from modes that proceed with edits.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func codexApprovalPolicy(_ value: String?, english: Bool) -> PermissionWording {
        guard let value else { return unset(english: english) }
        return switch value {
        case "untrusted":
            pair(
                "信頼対象外の操作を確認",
                "Confirm untrusted actions",
                "自動実行できる操作以外は承認を求めます。実行範囲はサンドボックス設定に従います。",
                "Asks for approval except for actions that can run automatically. Execution scope follows the sandbox setting.",
                english: english
            )
        case "on-request":
            pair(
                "必要時に承認を要求",
                "Ask when needed",
                "Codex が必要と判断したときに承認を求めます。実行範囲はサンドボックス設定に従います。",
                "Asks for approval when Codex decides it is needed. Execution scope follows the sandbox setting.",
                english: english
            )
        case "never":
            pair(
                "承認を要求しない",
                "Do not ask for approval",
                "承認を求めず、設定された実行制限の範囲で動作します。実行制限を解除する設定ではありません。",
                "Runs without asking for approval, within the configured execution limits. This does not lift those limits.",
                english: english
            )
        case "granular":
            pair(
                "項目別の承認設定",
                "Per-item approval",
                "承認要求の種類ごとに扱いを定める設定です。この名前だけでは具体的な許可範囲は分かりません。",
                "Defines how each kind of approval request is handled. This name alone does not describe the allowed scope.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func codexSandboxMode(_ value: String?, english: Bool) -> PermissionWording {
        guard let value else { return unset(english: english) }
        return switch value {
        case "read-only":
            pair(
                "読み取り専用",
                "Read-only",
                "サンドボックス内での書き込みを制限します。承認を求める条件は別の設定です。",
                "Restricts writes inside the sandbox. Approval conditions are a separate setting.",
                english: english
            )
        case "workspace-write":
            pair(
                "作業領域への書き込み",
                "Workspace write",
                "作業領域など、設定された範囲への書き込みを許可します。ネットワークや保護対象の制限は別途適用されます。",
                "Allows writes to the workspace and other configured scopes. Network and protected-path limits still apply.",
                english: english
            )
        case "danger-full-access":
            pair(
                "サンドボックス制限なし",
                "No sandbox limits",
                "Codex のサンドボックスによる実行制限を外します。承認を求める条件は別の設定です。",
                "Removes Codex sandbox execution limits. Approval conditions are a separate setting.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func codexProfile(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case ":read-only":
            pair(
                "読み取り専用",
                "Read Only",
                "読み取り専用のプロフィールです。承認方針の詳細はエージェントの設定を確認してください。",
                "A read-only profile. Check the agent settings for approval-policy details.",
                english: english
            )
        case ":workspace":
            pair(
                "作業領域への書き込み",
                "Auto",
                "作業領域への書き込みを許可するプロフィールです。承認方針の詳細はエージェントの設定を確認してください。",
                "A profile that allows workspace writes. Check the agent settings for approval-policy details.",
                english: english
            )
        case ":danger-full-access":
            pair(
                "承認なし・実行制限なし",
                "Full Access",
                "承認と実行制限を解除するプロフィールです。適用内容はエージェントの設定を確認してください。",
                "A profile that lifts approval and execution limits. Check the agent settings for what actually applies.",
                english: english
            )
        case nil:
            pair(
                "承認設定",
                "Approval",
                "プロフィールは未選択です。実際の適用内容はエージェントの設定を確認してください。",
                "No profile is selected. Check the agent settings for what actually applies.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func cursorApprovalMode(_ value: String?, english: Bool) -> PermissionWording {
        guard let value else { return unset(english: english) }
        return switch value {
        case "allowlist":
            pair(
                "許可リストで確認",
                "Confirm with allowlist",
                "許可リスト外の操作では確認を求める設定です。サンドボックス設定とは別です。",
                "Asks for confirmation outside the allowlist. This is separate from the sandbox setting.",
                english: english
            )
        case "unrestricted":
            pair(
                "承認確認を省略",
                "Skip approval prompts",
                "操作の承認確認を省略する設定です。サンドボックス設定とは別です。",
                "Skips approval prompts. This is separate from the sandbox setting.",
                english: english
            )
        case "auto-review":
            pair(
                "Cursor の自動判定",
                "Cursor auto review",
                "Cursor の判定に従って操作を実行します。Claude の権限モードや Codex の承認方針とは別の設定です。",
                "Runs actions according to Cursor's judgment. This is a different setting from Claude permission modes and Codex approval policy.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func cursorSandboxMode(_ value: String?, english: Bool) -> PermissionWording {
        guard let value else { return unset(english: english) }
        return switch value {
        case "enabled":
            pair(
                "実行制限を有効化",
                "Enable execution limits",
                "コマンドをサンドボックス内で実行する設定です。",
                "Runs commands inside a sandbox.",
                english: english
            )
        case "disabled":
            pair(
                "実行制限を無効化",
                "Disable execution limits",
                "サンドボックスによる実行制限を無効にする設定です。",
                "Disables sandbox execution limits.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func cursorOperationMode(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case nil:
            pair(
                "エージェント",
                "Agent",
                "通常の作業モードです。承認方式や実行制限を選ぶ項目ではありません。",
                "The usual working mode. This is not a control for approval method or execution limits.",
                english: english
            )
        case "ask":
            pair(
                "質問",
                "Ask",
                "質問向けの動作モードです。承認方式を選ぶ項目ではありません。",
                "A question-oriented working mode. This is not a control for choosing an approval method.",
                english: english
            )
        case "plan":
            pair(
                "計画",
                "Plan",
                "計画向けの動作モードです。承認方式や実行制限を選ぶ項目ではありません。",
                "A planning-oriented working mode. This is not a control for approval method or execution limits.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func claudeRuleBucket(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case "allow":
            pair(
                "許可",
                "Allow",
                "確認なしで実行を許可するルールです。拒否ルールなど、他の権限設定も適用されます。",
                "Permits execution without confirmation. Other permission settings, such as deny rules, also apply.",
                english: english
            )
        case "ask":
            pair(
                "確認する",
                "Ask to confirm",
                "実行前に確認を求めるルールです。確認できないモードでは実行が拒否される場合があります。",
                "Asks for confirmation before execution. In modes that cannot confirm, execution may be denied.",
                english: english
            )
        case "deny":
            pair(
                "拒否",
                "Deny",
                "実行を拒否するルールです。許可ルールより優先されます。",
                "Denies execution. Takes precedence over allow rules.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func cursorRuleBucket(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case "allow":
            pair(
                "許可",
                "Allow",
                "確認なしで実行を許可するルールです。拒否ルールが優先されます。",
                "Permits execution without confirmation. Deny rules take precedence.",
                english: english
            )
        case "deny":
            pair(
                "拒否",
                "Deny",
                "実行を拒否するルールです。許可ルールより優先されます。",
                "Denies execution. Takes precedence over allow rules.",
                english: english
            )
        default:
            unknown(value, english: english)
        }
    }

    private static func codexSettingKeyTitle(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case "approval_policy":
            PermissionWording(title: english ? "Approval policy" : "承認方針", explanation: "")
        case "sandbox_mode":
            PermissionWording(title: english ? "Execution limits (sandbox)" : "実行制限（サンドボックス）", explanation: "")
        default:
            unknown(value, english: english)
        }
    }

    private static func cursorSettingKeyTitle(_ value: String?, english: Bool) -> PermissionWording {
        switch value {
        case "approvalMode":
            PermissionWording(title: english ? "Approval method" : "承認方式", explanation: "")
        case "sandbox.mode":
            PermissionWording(title: english ? "Execution limits (sandbox)" : "実行制限（サンドボックス）", explanation: "")
        default:
            unknown(value, english: english)
        }
    }

    private static func claudePermissionsIntro(english: Bool) -> PermissionWording {
        pair(
            "権限",
            "Permissions",
            "対話 TUI の /permissions に相当します。~/.claude/settings.json の permissions を編集します。ルール編集は設定画面の起動時トグルとは別の設定です。",
            "Equivalent to /permissions in the interactive TUI. Edits permissions in ~/.claude/settings.json. Rule editing is a different setting from the launch toggle in Settings.",
            english: english
        )
    }

    private static func cursorPermissionsIntro(english: Bool) -> PermissionWording {
        pair(
            "権限",
            "Permissions",
            "~/.cursor/cli-config.json の permissions を編集します。拒否は許可より優先されます。ルール編集は設定画面の起動時トグルとは別の設定です。",
            "Edits permissions in ~/.cursor/cli-config.json. Deny rules take precedence over allow. Rule editing is a different setting from the launch toggle in Settings.",
            english: english
        )
    }
}
