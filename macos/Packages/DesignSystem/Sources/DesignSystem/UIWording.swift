/// UX-10a 一般操作文言の正本。引数の言語コードだけで結果が決まり、I/O や言語キャッシュを持たない。
public enum UIWording {
    public enum Key: String, CaseIterable, Equatable, Hashable, Sendable {
        case composerPlaceholder
        case errorHeading
        case missingCommand
        case outputAvailable
        case missingSubAgentDescription
        case copyAction
        case copyCodeHelp
        case copyMessageHelp
        case copiedFeedback
        case missingCodeBlockLanguage
        case missingMarkdownLanguage
        case acceptAction
        case declineAction
        case cancelAction
        case modelLabel
        case reasoningEffortLabel
        case permissionLabel
        case approvalLabel
        case modeLabel
        case planOption
        case effortLow
        case effortMedium
        case effortHigh
        case effortXHigh
        case effortMax
        case refreshAction
        case missingBranch
        case branchCheckoutFailed
        case noLocalBranches
        case contextWindowHeading
        case projectsHeading
    }

    public static func text(_ key: Key, languageCode: String) -> String {
        let english = isEnglish(languageCode)
        return switch key {
        case .composerPlaceholder:
            english ? "Enter a message" : "メッセージを入力"
        case .errorHeading:
            english ? "Error" : "エラー"
        case .missingCommand:
            english ? "Command" : "コマンド"
        case .outputAvailable:
            english ? "Output available" : "出力あり"
        case .missingSubAgentDescription:
            english ? "Sub-agent" : "サブエージェント"
        case .copyAction:
            english ? "Copy" : "コピー"
        case .copyCodeHelp:
            english ? "Copy code" : "コードをコピー"
        case .copyMessageHelp:
            english ? "Copy message" : "メッセージをコピー"
        case .copiedFeedback:
            english ? "Copied" : "コピーしました"
        case .missingCodeBlockLanguage:
            english ? "text" : "テキスト"
        case .missingMarkdownLanguage:
            english ? "code" : "コード"
        case .acceptAction:
            english ? "Accept" : "承認"
        case .declineAction:
            english ? "Decline" : "拒否"
        case .cancelAction:
            english ? "Cancel" : "キャンセル"
        case .modelLabel:
            english ? "Model" : "モデル"
        case .reasoningEffortLabel:
            english ? "Reasoning Effort" : "思考の深さ"
        case .permissionLabel:
            english ? "Permission" : "承認設定"
        case .approvalLabel:
            english ? "Approval" : "承認設定"
        case .modeLabel:
            english ? "Mode" : "動作モード"
        case .planOption:
            english ? "Plan" : "計画"
        case .effortLow:
            english ? "Low" : "低"
        case .effortMedium:
            english ? "Medium" : "中"
        case .effortHigh:
            english ? "High" : "高"
        case .effortXHigh:
            english ? "X High" : "非常に高"
        case .effortMax:
            english ? "Max" : "最大"
        case .refreshAction:
            english ? "Refresh" : "更新"
        case .missingBranch:
            english ? "Branch" : "ブランチ"
        case .branchCheckoutFailed:
            english ? "Branch checkout failed" : "ブランチの切り替えに失敗しました"
        case .noLocalBranches:
            english ? "No local branches" : "ローカルブランチがありません"
        case .contextWindowHeading:
            english ? "Context window:" : "コンテキスト容量:"
        case .projectsHeading:
            english ? "Projects" : "プロジェクト"
        }
    }

    public static func contextUsagePercent(
        usedPercent: Int,
        remainingPercent: Int,
        languageCode: String
    ) -> String {
        if isEnglish(languageCode) {
            "\(usedPercent)% used (\(remainingPercent)% left)"
        } else {
            "使用 \(usedPercent)%（残り \(remainingPercent)%）"
        }
    }

    public static func contextTokenUsage(
        usedText: String,
        windowText: String,
        languageCode: String
    ) -> String {
        if isEnglish(languageCode) {
            "\(usedText) / \(windowText) tokens used"
        } else {
            "\(usedText) / \(windowText) トークン使用"
        }
    }

    public static func turnCostAccessibility(amountText: String, languageCode: String) -> String {
        if isEnglish(languageCode) {
            "Turn cost \(amountText)"
        } else {
            "この応答の費用 \(amountText)"
        }
    }

    private static func isEnglish(_ languageCode: String) -> Bool {
        primaryLanguage(languageCode) == "en"
    }

    private static func primaryLanguage(_ languageCode: String) -> String {
        let first = languageCode.split { $0 == "-" || $0 == "_" }.first.map(String.init) ?? ""
        return first.lowercased()
    }
}
