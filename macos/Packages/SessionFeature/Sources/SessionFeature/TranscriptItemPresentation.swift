import Foundation

/// トランスクリプト項目の表示分類・見出し・開閉・意味色。ViewModel や I/O に触れない同期的な値型。
struct TranscriptItemPresentation: Equatable, Sendable {
    enum Classification: Equatable, Sendable {
        case answer
        case detail
        case status
        case error
    }

    enum SemanticInk: Equatable, Sendable {
        case normal
        case process
        case error
    }

    enum CommandPath: Equatable, Sendable {
        case single
        case group
    }

    let isVisible: Bool
    let classification: Classification
    let heading: String?
    let subtitle: String?
    let isCollapsible: Bool
    let defaultExpanded: Bool
    let semanticInk: SemanticInk
    let expandedBody: String?

    static func isExpanded(userOverride: Bool?, defaultExpanded: Bool) -> Bool {
        userOverride ?? defaultExpanded
    }

    static func retainedUserOverride(previous: Bool?, remainedMounted: Bool) -> Bool? {
        remainedMounted ? previous : nil
    }

    static func answer(text: String) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .answer,
            heading: nil,
            subtitle: nil,
            isCollapsible: false,
            defaultExpanded: true,
            semanticInk: .normal,
            expandedBody: text
        )
    }

    static func reasoning(text: String, summary: String?) -> TranscriptItemPresentation {
        let visible = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return TranscriptItemPresentation(
            isVisible: visible,
            classification: .detail,
            heading: "思考",
            subtitle: summary,
            isCollapsible: true,
            defaultExpanded: false,
            semanticInk: .process,
            expandedBody: text
        )
    }

    static func command(
        path: CommandPath,
        itemCount: Int,
        isRunning: Bool,
        hasNonBlankOutput: Bool,
        hasFailed: Bool = false,
        runningSubtitle: String = "実行中",
        outputAvailableSubtitle: String = "出力あり"
    ) -> TranscriptItemPresentation {
        let visible: Bool
        switch path {
        case .single:
            visible = isRunning || hasNonBlankOutput
        case .group:
            visible = isRunning || itemCount == 1 || hasNonBlankOutput
        }
        let subtitle: String?
        if isRunning {
            subtitle = runningSubtitle
        } else if hasNonBlankOutput {
            subtitle = outputAvailableSubtitle
        } else {
            subtitle = nil
        }
        return TranscriptItemPresentation(
            isVisible: visible,
            classification: .detail,
            // 04 A1: 1 件は「コマンド」の単独カード、2 件以上は「ツール実行 ×n」（ユーザー承認 2026-09-24）。
            heading: itemCount == 1 ? "コマンド" : "ツール実行 ×\(itemCount)",
            subtitle: subtitle,
            isCollapsible: true,
            // 04 B1: 実行中の束だけ既定で開く（ユーザー承認 2026-09-24）。
            // 04「カードの既定の開き方」: コマンド単体は失敗（exit ≠ 0）したものも開いておく（C-22）。
            defaultExpanded: isRunning || (path == .single && hasFailed),
            semanticInk: .process,
            expandedBody: nil
        )
    }

    static func fileChange(title: String) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .detail,
            heading: title,
            subtitle: nil,
            isCollapsible: true,
            defaultExpanded: false,
            semanticInk: .process,
            expandedBody: nil
        )
    }

    /// 見出しは「タスク 完了数/全数」（04 A1。ユーザー承認 2026-09-24）。
    /// 04「カードの既定の開き方」: いちばん新しいタスクリストだけ開き、古いものは閉じる（C-16）。
    static func taskList(count: Int, completed: Int = 0, isLatest: Bool = false) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .detail,
            heading: "タスク \(completed)/\(count)",
            subtitle: nil,
            isCollapsible: true,
            defaultExpanded: isLatest,
            semanticInk: .process,
            expandedBody: count == 0 ? "タスクなし" : nil
        )
    }

    static func activity(label: String) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .status,
            heading: label,
            subtitle: nil,
            isCollapsible: false,
            defaultExpanded: true,
            semanticInk: .process,
            expandedBody: nil
        )
    }

    static func error(message: String, heading: String = "エラー") -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .error,
            heading: heading,
            subtitle: nil,
            isCollapsible: false,
            defaultExpanded: true,
            semanticInk: .error,
            expandedBody: message
        )
    }
}
