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
            heading: "思考の詳細",
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
        hasNonBlankOutput: Bool
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
            subtitle = "実行中"
        } else if hasNonBlankOutput {
            subtitle = "出力あり"
        } else {
            subtitle = nil
        }
        return TranscriptItemPresentation(
            isVisible: visible,
            classification: .detail,
            heading: "処理の詳細（\(itemCount)件）",
            subtitle: subtitle,
            isCollapsible: true,
            defaultExpanded: false,
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

    static func taskList(count: Int) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .detail,
            heading: "タスク（\(count)件）",
            subtitle: nil,
            isCollapsible: true,
            defaultExpanded: false,
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

    static func error(message: String) -> TranscriptItemPresentation {
        TranscriptItemPresentation(
            isVisible: true,
            classification: .error,
            heading: "エラー",
            subtitle: nil,
            isCollapsible: false,
            defaultExpanded: true,
            semanticInk: .error,
            expandedBody: message
        )
    }
}
