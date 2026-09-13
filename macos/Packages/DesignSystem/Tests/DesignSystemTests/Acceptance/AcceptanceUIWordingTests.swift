// 実パス: macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceUIWordingTests.swift
// task-48（UX-10a）受け入れテスト（PM 著・不変）。UIWording 未実装のコンパイル RED が正常。
// 期待値は tasks/task-48.md の独立リテラル。製品の辞書・列挙・出力から生成しない。
//
// 凍結する公開面:
//   enum UIWording
//   enum UIWording.Key: String, CaseIterable, Equatable, Hashable, Sendable
//   static func text(_ key: Key, languageCode: String) -> String
//   static func contextUsagePercent(usedPercent: Int, remainingPercent: Int, languageCode: String) -> String
//   static func contextTokenUsage(usedText: String, windowText: String, languageCode: String) -> String
//   static func turnCostAccessibility(amountText: String, languageCode: String) -> String
// 言語: 主言語（`-` / `_` の前）を大小無視で見る。en は英語、ja は日本語、それ以外は日本語。

import Testing
@testable import DesignSystem

private func requireKeyTraits<T: CaseIterable & Equatable & Hashable & Sendable>(_: T.Type) {}

private enum FrozenForbiddenWording {
    static let askPhloxAnything = "Ask Phlox anything..."
    static let legacyXHigh = "XHigh"
    static let legacyEffortEnglish = "Effort"
    static let approvalRequested = "Approval requested"
    static let fullAccess = "Full Access"
    static let bypass = "Bypass"
    static let appServerSystemError = "app-server system error"
}

private struct WordingRow: Sendable {
    let key: UIWording.Key
    let japanese: String
    let english: String
    let name: String
}

@Suite("task-48: UIWording 操作文言の正本")
struct AcceptanceUIWordingTests {

    /// 契約「凍結する一般文言」表。実装の allCases や辞書から作らない。
    private static let rows: [WordingRow] = [
        WordingRow(key: .composerPlaceholder, japanese: "メッセージを入力", english: "Enter a message", name: "composerPlaceholder"),
        WordingRow(key: .errorHeading, japanese: "エラー", english: "Error", name: "errorHeading"),
        WordingRow(key: .missingCommand, japanese: "コマンド", english: "Command", name: "missingCommand"),
        WordingRow(key: .outputAvailable, japanese: "出力あり", english: "Output available", name: "outputAvailable"),
        WordingRow(key: .missingSubAgentDescription, japanese: "サブエージェント", english: "Sub-agent", name: "missingSubAgentDescription"),
        WordingRow(key: .copyAction, japanese: "コピー", english: "Copy", name: "copyAction"),
        WordingRow(key: .copyCodeHelp, japanese: "コードをコピー", english: "Copy code", name: "copyCodeHelp"),
        WordingRow(key: .copyMessageHelp, japanese: "メッセージをコピー", english: "Copy message", name: "copyMessageHelp"),
        WordingRow(key: .copiedFeedback, japanese: "コピーしました", english: "Copied", name: "copiedFeedback"),
        WordingRow(key: .missingCodeBlockLanguage, japanese: "テキスト", english: "text", name: "missingCodeBlockLanguage"),
        WordingRow(key: .missingMarkdownLanguage, japanese: "コード", english: "code", name: "missingMarkdownLanguage"),
        WordingRow(key: .acceptAction, japanese: "承認", english: "Accept", name: "acceptAction"),
        WordingRow(key: .declineAction, japanese: "拒否", english: "Decline", name: "declineAction"),
        WordingRow(key: .cancelAction, japanese: "キャンセル", english: "Cancel", name: "cancelAction"),
        WordingRow(key: .modelLabel, japanese: "モデル", english: "Model", name: "modelLabel"),
        WordingRow(key: .reasoningEffortLabel, japanese: "思考の深さ", english: "Reasoning Effort", name: "reasoningEffortLabel"),
        WordingRow(key: .permissionLabel, japanese: "承認設定", english: "Permission", name: "permissionLabel"),
        WordingRow(key: .approvalLabel, japanese: "承認設定", english: "Approval", name: "approvalLabel"),
        WordingRow(key: .modeLabel, japanese: "動作モード", english: "Mode", name: "modeLabel"),
        WordingRow(key: .planOption, japanese: "計画", english: "Plan", name: "planOption"),
        WordingRow(key: .effortLow, japanese: "低", english: "Low", name: "effortLow"),
        WordingRow(key: .effortMedium, japanese: "中", english: "Medium", name: "effortMedium"),
        WordingRow(key: .effortHigh, japanese: "高", english: "High", name: "effortHigh"),
        WordingRow(key: .effortXHigh, japanese: "非常に高", english: "X High", name: "effortXHigh"),
        WordingRow(key: .effortMax, japanese: "最大", english: "Max", name: "effortMax"),
        WordingRow(key: .refreshAction, japanese: "更新", english: "Refresh", name: "refreshAction"),
        WordingRow(key: .missingBranch, japanese: "ブランチ", english: "Branch", name: "missingBranch"),
        WordingRow(key: .branchCheckoutFailed, japanese: "ブランチの切り替えに失敗しました", english: "Branch checkout failed", name: "branchCheckoutFailed"),
        WordingRow(key: .noLocalBranches, japanese: "ローカルブランチがありません", english: "No local branches", name: "noLocalBranches"),
        WordingRow(key: .contextWindowHeading, japanese: "コンテキスト容量:", english: "Context window:", name: "contextWindowHeading"),
        WordingRow(key: .projectsHeading, japanese: "プロジェクト", english: "Projects", name: "projectsHeading"),
    ]

    @Test("Key の命名規則と集合が契約表 31 件と一致する")
    func keyNamingMatchesContractTable() {
        requireKeyTraits(UIWording.Key.self)
        #expect(Self.rows.count == 31)
        #expect(Set(Self.rows.map(\.key)).count == 31)
        #expect(UIWording.Key.allCases.count == 31)
        #expect(UIWording.Key.allCases == Self.rows.map(\.key))
        #expect(UIWording.Key.composerPlaceholder.rawValue == "composerPlaceholder")
        #expect(UIWording.Key.errorHeading.rawValue == "errorHeading")
        #expect(UIWording.Key.missingCommand.rawValue == "missingCommand")
        #expect(UIWording.Key.outputAvailable.rawValue == "outputAvailable")
        #expect(UIWording.Key.missingSubAgentDescription.rawValue == "missingSubAgentDescription")
        #expect(UIWording.Key.copyAction.rawValue == "copyAction")
        #expect(UIWording.Key.copyCodeHelp.rawValue == "copyCodeHelp")
        #expect(UIWording.Key.copyMessageHelp.rawValue == "copyMessageHelp")
        #expect(UIWording.Key.copiedFeedback.rawValue == "copiedFeedback")
        #expect(UIWording.Key.missingCodeBlockLanguage.rawValue == "missingCodeBlockLanguage")
        #expect(UIWording.Key.missingMarkdownLanguage.rawValue == "missingMarkdownLanguage")
        #expect(UIWording.Key.acceptAction.rawValue == "acceptAction")
        #expect(UIWording.Key.declineAction.rawValue == "declineAction")
        #expect(UIWording.Key.cancelAction.rawValue == "cancelAction")
        #expect(UIWording.Key.modelLabel.rawValue == "modelLabel")
        #expect(UIWording.Key.reasoningEffortLabel.rawValue == "reasoningEffortLabel")
        #expect(UIWording.Key.permissionLabel.rawValue == "permissionLabel")
        #expect(UIWording.Key.approvalLabel.rawValue == "approvalLabel")
        #expect(UIWording.Key.modeLabel.rawValue == "modeLabel")
        #expect(UIWording.Key.planOption.rawValue == "planOption")
        #expect(UIWording.Key.effortLow.rawValue == "effortLow")
        #expect(UIWording.Key.effortMedium.rawValue == "effortMedium")
        #expect(UIWording.Key.effortHigh.rawValue == "effortHigh")
        #expect(UIWording.Key.effortXHigh.rawValue == "effortXHigh")
        #expect(UIWording.Key.effortMax.rawValue == "effortMax")
        #expect(UIWording.Key.refreshAction.rawValue == "refreshAction")
        #expect(UIWording.Key.missingBranch.rawValue == "missingBranch")
        #expect(UIWording.Key.branchCheckoutFailed.rawValue == "branchCheckoutFailed")
        #expect(UIWording.Key.noLocalBranches.rawValue == "noLocalBranches")
        #expect(UIWording.Key.contextWindowHeading.rawValue == "contextWindowHeading")
        #expect(UIWording.Key.projectsHeading.rawValue == "projectsHeading")
    }

    @Test("公開関数の型が text(_:languageCode:) である")
    func publicFunctionSignature() {
        let text: (UIWording.Key, String) -> String = UIWording.text
        let percent: (Int, Int, String) -> String = UIWording.contextUsagePercent
        let tokens: (String, String, String) -> String = UIWording.contextTokenUsage
        let cost: (String, String) -> String = UIWording.turnCostAccessibility
        #expect(text(.copyAction, "ja") == "コピー")
        #expect(percent(12, 88, "en") == "12% used (88% left)")
        #expect(tokens("12", "200", "ja") == "12 / 200 トークン使用")
        #expect(cost("$0.01", "en") == "Turn cost $0.01")
    }

    @Test("日本語の一般文言が契約表の独立リテラルと逐語一致する")
    func japaneseMatchesContractLiterals() {
        #expect(UIWording.text(.composerPlaceholder, languageCode: "ja") == "メッセージを入力")
        #expect(UIWording.text(.errorHeading, languageCode: "ja") == "エラー")
        #expect(UIWording.text(.missingCommand, languageCode: "ja") == "コマンド")
        #expect(UIWording.text(.outputAvailable, languageCode: "ja") == "出力あり")
        #expect(UIWording.text(.missingSubAgentDescription, languageCode: "ja") == "サブエージェント")
        #expect(UIWording.text(.copyAction, languageCode: "ja") == "コピー")
        #expect(UIWording.text(.copyCodeHelp, languageCode: "ja") == "コードをコピー")
        #expect(UIWording.text(.copyMessageHelp, languageCode: "ja") == "メッセージをコピー")
        #expect(UIWording.text(.copiedFeedback, languageCode: "ja") == "コピーしました")
        #expect(UIWording.text(.missingCodeBlockLanguage, languageCode: "ja") == "テキスト")
        #expect(UIWording.text(.missingMarkdownLanguage, languageCode: "ja") == "コード")
        #expect(UIWording.text(.acceptAction, languageCode: "ja") == "承認")
        #expect(UIWording.text(.declineAction, languageCode: "ja") == "拒否")
        #expect(UIWording.text(.cancelAction, languageCode: "ja") == "キャンセル")
        #expect(UIWording.text(.modelLabel, languageCode: "ja") == "モデル")
        #expect(UIWording.text(.reasoningEffortLabel, languageCode: "ja") == "思考の深さ")
        #expect(UIWording.text(.permissionLabel, languageCode: "ja") == "承認設定")
        #expect(UIWording.text(.approvalLabel, languageCode: "ja") == "承認設定")
        #expect(UIWording.text(.modeLabel, languageCode: "ja") == "動作モード")
        #expect(UIWording.text(.planOption, languageCode: "ja") == "計画")
        #expect(UIWording.text(.effortLow, languageCode: "ja") == "低")
        #expect(UIWording.text(.effortMedium, languageCode: "ja") == "中")
        #expect(UIWording.text(.effortHigh, languageCode: "ja") == "高")
        #expect(UIWording.text(.effortXHigh, languageCode: "ja") == "非常に高")
        #expect(UIWording.text(.effortMax, languageCode: "ja") == "最大")
        #expect(UIWording.text(.refreshAction, languageCode: "ja") == "更新")
        #expect(UIWording.text(.missingBranch, languageCode: "ja") == "ブランチ")
        #expect(UIWording.text(.branchCheckoutFailed, languageCode: "ja") == "ブランチの切り替えに失敗しました")
        #expect(UIWording.text(.noLocalBranches, languageCode: "ja") == "ローカルブランチがありません")
        #expect(UIWording.text(.contextWindowHeading, languageCode: "ja") == "コンテキスト容量:")
        #expect(UIWording.text(.projectsHeading, languageCode: "ja") == "プロジェクト")
    }

    @Test("英語の一般文言が契約表の独立リテラルと逐語一致する")
    func englishMatchesContractLiterals() {
        #expect(UIWording.text(.composerPlaceholder, languageCode: "en") == "Enter a message")
        #expect(UIWording.text(.errorHeading, languageCode: "en") == "Error")
        #expect(UIWording.text(.missingCommand, languageCode: "en") == "Command")
        #expect(UIWording.text(.outputAvailable, languageCode: "en") == "Output available")
        #expect(UIWording.text(.missingSubAgentDescription, languageCode: "en") == "Sub-agent")
        #expect(UIWording.text(.copyAction, languageCode: "en") == "Copy")
        #expect(UIWording.text(.copyCodeHelp, languageCode: "en") == "Copy code")
        #expect(UIWording.text(.copyMessageHelp, languageCode: "en") == "Copy message")
        #expect(UIWording.text(.copiedFeedback, languageCode: "en") == "Copied")
        #expect(UIWording.text(.missingCodeBlockLanguage, languageCode: "en") == "text")
        #expect(UIWording.text(.missingMarkdownLanguage, languageCode: "en") == "code")
        #expect(UIWording.text(.acceptAction, languageCode: "en") == "Accept")
        #expect(UIWording.text(.declineAction, languageCode: "en") == "Decline")
        #expect(UIWording.text(.cancelAction, languageCode: "en") == "Cancel")
        #expect(UIWording.text(.modelLabel, languageCode: "en") == "Model")
        #expect(UIWording.text(.reasoningEffortLabel, languageCode: "en") == "Reasoning Effort")
        #expect(UIWording.text(.permissionLabel, languageCode: "en") == "Permission")
        #expect(UIWording.text(.approvalLabel, languageCode: "en") == "Approval")
        #expect(UIWording.text(.modeLabel, languageCode: "en") == "Mode")
        #expect(UIWording.text(.planOption, languageCode: "en") == "Plan")
        #expect(UIWording.text(.effortLow, languageCode: "en") == "Low")
        #expect(UIWording.text(.effortMedium, languageCode: "en") == "Medium")
        #expect(UIWording.text(.effortHigh, languageCode: "en") == "High")
        #expect(UIWording.text(.effortXHigh, languageCode: "en") == "X High")
        #expect(UIWording.text(.effortMax, languageCode: "en") == "Max")
        #expect(UIWording.text(.refreshAction, languageCode: "en") == "Refresh")
        #expect(UIWording.text(.missingBranch, languageCode: "en") == "Branch")
        #expect(UIWording.text(.branchCheckoutFailed, languageCode: "en") == "Branch checkout failed")
        #expect(UIWording.text(.noLocalBranches, languageCode: "en") == "No local branches")
        #expect(UIWording.text(.contextWindowHeading, languageCode: "en") == "Context window:")
        #expect(UIWording.text(.projectsHeading, languageCode: "en") == "Projects")
    }

    @Test("表の各行を日英で再取得しても同じ独立リテラルになる")
    func eachRowReacquiredInBothLanguages() {
        for row in Self.rows {
            #expect(UIWording.text(row.key, languageCode: "ja") == row.japanese, Comment(rawValue: "\(row.name) ja"))
            #expect(UIWording.text(row.key, languageCode: "en") == row.english, Comment(rawValue: "\(row.name) en"))
            #expect(UIWording.text(row.key, languageCode: "ja") == UIWording.text(row.key, languageCode: "ja"), Comment(rawValue: "\(row.name) ja stable"))
            #expect(UIWording.text(row.key, languageCode: "en") == UIWording.text(row.key, languageCode: "en"), Comment(rawValue: "\(row.name) en stable"))
        }
    }

    @Test("3入力欄の共通キー composerPlaceholder の日英")
    func sharedComposerPlaceholderKey() {
        #expect(UIWording.text(.composerPlaceholder, languageCode: "ja") == "メッセージを入力")
        #expect(UIWording.text(.composerPlaceholder, languageCode: "en") == "Enter a message")
        #expect(UIWording.Key.composerPlaceholder == UIWording.Key.composerPlaceholder)
    }

    @Test("未対応言語と空コードは日本語へフォールバックする")
    func unsupportedLanguageFallsBackToJapanese() {
        #expect(UIWording.text(.copyAction, languageCode: "zh") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "fr") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "fr-FR") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "pt-BR") == "コピー")
        #expect(UIWording.text(.composerPlaceholder, languageCode: "de") == "メッセージを入力")
        #expect(UIWording.text(.projectsHeading, languageCode: "ko") == "プロジェクト")
    }

    @Test("地域付き Locale と大小は同じ規則で扱う")
    func regionalAndCasedLanguageCodes() {
        #expect(UIWording.text(.copyAction, languageCode: "ja-JP") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "ja_JP") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "JA") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "Ja") == "コピー")
        #expect(UIWording.text(.copyAction, languageCode: "en-US") == "Copy")
        #expect(UIWording.text(.copyAction, languageCode: "en_GB") == "Copy")
        #expect(UIWording.text(.copyAction, languageCode: "EN") == "Copy")
        #expect(UIWording.text(.copyAction, languageCode: "En") == "Copy")
        #expect(UIWording.text(.composerPlaceholder, languageCode: "en-US") == "Enter a message")
        #expect(UIWording.text(.composerPlaceholder, languageCode: "ja-JP") == "メッセージを入力")
    }

    @Test("言語を変えて再取得すると日英が入れ替わり、戻すと元に戻る")
    func languageSwitchThenRestore() {
        let firstJA = UIWording.text(.modelLabel, languageCode: "ja")
        let thenEN = UIWording.text(.modelLabel, languageCode: "en")
        let backJA = UIWording.text(.modelLabel, languageCode: "ja")
        #expect(firstJA == "モデル")
        #expect(thenEN == "Model")
        #expect(backJA == "モデル")
        #expect(firstJA == backJA)
        #expect(firstJA != thenEN)

        let firstEN = UIWording.text(.copiedFeedback, languageCode: "en")
        let thenJA = UIWording.text(.copiedFeedback, languageCode: "ja")
        let backEN = UIWording.text(.copiedFeedback, languageCode: "en")
        #expect(firstEN == "Copied")
        #expect(thenJA == "コピーしました")
        #expect(backEN == "Copied")
    }

    @Test("permission と approval は日本語が同じでも英語キーが異なる")
    func permissionAndApprovalShareJapaneseNotEnglish() {
        #expect(UIWording.text(.permissionLabel, languageCode: "ja") == "承認設定")
        #expect(UIWording.text(.approvalLabel, languageCode: "ja") == "承認設定")
        #expect(UIWording.text(.permissionLabel, languageCode: "en") == "Permission")
        #expect(UIWording.text(.approvalLabel, languageCode: "en") == "Approval")
        #expect(UIWording.Key.permissionLabel != UIWording.Key.approvalLabel)
    }

    @Test("コードブロックと言語名欠損の Markdown は別キー")
    func missingLanguageKeysAreDistinct() {
        #expect(UIWording.text(.missingCodeBlockLanguage, languageCode: "ja") == "テキスト")
        #expect(UIWording.text(.missingMarkdownLanguage, languageCode: "ja") == "コード")
        #expect(UIWording.text(.missingCodeBlockLanguage, languageCode: "en") == "text")
        #expect(UIWording.text(.missingMarkdownLanguage, languageCode: "en") == "code")
        #expect(UIWording.Key.missingCodeBlockLanguage != UIWording.Key.missingMarkdownLanguage)
    }

    @Test("期待値は禁止語（旧混在・権限・状態説明）を使わない")
    func expectedValuesRejectForbiddenLegacyWording() {
        #expect(UIWording.text(.composerPlaceholder, languageCode: "en") != FrozenForbiddenWording.askPhloxAnything)
        #expect(UIWording.text(.composerPlaceholder, languageCode: "ja") != FrozenForbiddenWording.askPhloxAnything)
        #expect(UIWording.text(.effortXHigh, languageCode: "en") != FrozenForbiddenWording.legacyXHigh)
        #expect(UIWording.text(.effortXHigh, languageCode: "en") == "X High")
        #expect(UIWording.text(.reasoningEffortLabel, languageCode: "en") != FrozenForbiddenWording.legacyEffortEnglish)
        #expect(UIWording.text(.reasoningEffortLabel, languageCode: "en") == "Reasoning Effort")
        #expect(UIWording.text(.errorHeading, languageCode: "en") != FrozenForbiddenWording.approvalRequested)
        #expect(UIWording.text(.permissionLabel, languageCode: "en") != FrozenForbiddenWording.fullAccess)
        #expect(UIWording.text(.permissionLabel, languageCode: "en") != FrozenForbiddenWording.bypass)
        #expect(UIWording.text(.errorHeading, languageCode: "en") != FrozenForbiddenWording.appServerSystemError)
        for row in Self.rows {
            #expect(row.japanese != FrozenForbiddenWording.askPhloxAnything, Comment(rawValue: "\(row.name) ja forbidden"))
            #expect(row.english != FrozenForbiddenWording.askPhloxAnything, Comment(rawValue: "\(row.name) en forbidden"))
            #expect(row.english != FrozenForbiddenWording.legacyXHigh, Comment(rawValue: "\(row.name) XHigh"))
            #expect(row.english != FrozenForbiddenWording.approvalRequested, Comment(rawValue: "\(row.name) approval requested"))
            #expect(row.english != FrozenForbiddenWording.fullAccess, Comment(rawValue: "\(row.name) Full Access"))
            #expect(row.english != FrozenForbiddenWording.bypass, Comment(rawValue: "\(row.name) Bypass"))
        }
    }

    @Test("コンテキスト使用率テンプレートは値の欠落・逆転・固定を検出する")
    func contextUsagePercentTemplate() {
        #expect(UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "ja") == "使用 12%（残り 88%）")
        #expect(UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "en") == "12% used (88% left)")
        #expect(UIWording.contextUsagePercent(usedPercent: 0, remainingPercent: 100, languageCode: "ja") == "使用 0%（残り 100%）")
        #expect(UIWording.contextUsagePercent(usedPercent: 0, remainingPercent: 100, languageCode: "en") == "0% used (100% left)")
        #expect(UIWording.contextUsagePercent(usedPercent: 3, remainingPercent: 97, languageCode: "ja") == "使用 3%（残り 97%）")
        #expect(UIWording.contextUsagePercent(usedPercent: 100, remainingPercent: 0, languageCode: "en") == "100% used (0% left)")
        let forwardJA = UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "ja")
        let swappedJA = UIWording.contextUsagePercent(usedPercent: 88, remainingPercent: 12, languageCode: "ja")
        #expect(forwardJA != swappedJA)
        #expect(swappedJA == "使用 88%（残り 12%）")
        let forwardEN = UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "en")
        let swappedEN = UIWording.contextUsagePercent(usedPercent: 88, remainingPercent: 12, languageCode: "en")
        #expect(forwardEN != swappedEN)
        #expect(UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "zh") == "使用 12%（残り 88%）")
        #expect(UIWording.contextUsagePercent(usedPercent: 12, remainingPercent: 88, languageCode: "en-US") == "12% used (88% left)")
        #expect(forwardJA.contains("12"))
        #expect(forwardJA.contains("88"))
        #expect(!forwardJA.contains("{"))
        #expect(!forwardEN.contains("{"))
    }

    @Test("コンテキスト使用量テンプレートは挿入値を保持し逆転を検出する")
    func contextTokenUsageTemplate() {
        #expect(UIWording.contextTokenUsage(usedText: "1.2k", windowText: "8k", languageCode: "ja") == "1.2k / 8k トークン使用")
        #expect(UIWording.contextTokenUsage(usedText: "1.2k", windowText: "8k", languageCode: "en") == "1.2k / 8k tokens used")
        #expect(UIWording.contextTokenUsage(usedText: "12", windowText: "200", languageCode: "ja") == "12 / 200 トークン使用")
        #expect(UIWording.contextTokenUsage(usedText: "12", windowText: "200", languageCode: "en") == "12 / 200 tokens used")
        #expect(UIWording.contextTokenUsage(usedText: "0", windowText: "8.0k", languageCode: "en") == "0 / 8.0k tokens used")
        let forward = UIWording.contextTokenUsage(usedText: "12", windowText: "200", languageCode: "ja")
        let swapped = UIWording.contextTokenUsage(usedText: "200", windowText: "12", languageCode: "ja")
        #expect(forward != swapped)
        #expect(swapped == "200 / 12 トークン使用")
        #expect(UIWording.contextTokenUsage(usedText: "12", windowText: "200", languageCode: "fr") == "12 / 200 トークン使用")
        #expect(!forward.contains("{"))
    }

    @Test("応答費用の AX ラベルは既存の金額表示をそのまま挿入する")
    func turnCostAccessibilityTemplate() {
        #expect(UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "ja") == "この応答の費用 $0.0123")
        #expect(UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "en") == "Turn cost $0.0123")
        #expect(UIWording.turnCostAccessibility(amountText: "$1.00", languageCode: "ja") == "この応答の費用 $1.00")
        #expect(UIWording.turnCostAccessibility(amountText: "$1.00", languageCode: "en") == "Turn cost $1.00")
        #expect(UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "en") != UIWording.turnCostAccessibility(amountText: "$1.00", languageCode: "en"))
        #expect(UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "zh") == "この応答の費用 $0.0123")
        #expect(UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "en-US") == "Turn cost $0.0123")
        let ja = UIWording.turnCostAccessibility(amountText: "$0.0123", languageCode: "ja")
        #expect(ja.contains("$0.0123"))
        #expect(!ja.contains("{"))
    }
}
