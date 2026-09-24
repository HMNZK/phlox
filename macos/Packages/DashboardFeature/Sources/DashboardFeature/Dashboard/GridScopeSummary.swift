import Foundation
import AgentDomain
import DesignSystem

/// グリッドの表示範囲と実表示件数の要約。文言の正本。
struct GridScopeSummary: Equatable {
    enum ClearAction: Equatable, Hashable {
        case projectFilter
        case sessionSelection

        var label: String {
            switch self {
            case .projectFilter:
                "プロジェクトの絞り込みを解除"
            case .sessionSelection:
                "セッションの選択を解除"
            }
        }
    }

    let title: String
    let countText: String
    let isEmpty: Bool
    let emptyMessage: String?
    let clearActions: [ClearAction]

    var text: String {
        "\(title)\u{30FB}\(countText)"
    }

    var accessibilityText: String {
        guard !clearActions.isEmpty else { return text }
        return ([text] + clearActions.map(\.label)).joined(separator: "。")
    }

    static func make(
        isProjectFiltered: Bool,
        projectName: String?,
        visibleCount: Int,
        hasSessionSelection: Bool,
        locale: Locale = Locale(identifier: "ja")
    ) -> GridScopeSummary {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title: String
        if !isProjectFiltered {
            title = "すべてのプロジェクト"
        } else if trimmed.isEmpty {
            title = "名称未設定のプロジェクト"
        } else {
            title = trimmed
        }

        let countText = "\(max(0, visibleCount))件"
        let isEmpty = visibleCount <= 0
        let emptyMessage: String?
        if isEmpty {
            // 06 S10: 選んだセッションが見えないときは「〈プロジェクト〉の中で、選んだセッションがすべて終了または削除されました。」。
            if hasSessionSelection, isProjectFiltered {
                emptyMessage = String(format: AppLocalizedString.string("%@ の中で、選んだセッションがすべて終了または削除されました。", locale: locale), title)
            } else if hasSessionSelection {
                emptyMessage = AppLocalizedString.string("選んだセッションがすべて終了または削除されました。", locale: locale)
            } else if isProjectFiltered {
                emptyMessage = AppLocalizedString.string("このプロジェクトに表示できるセッションがありません", locale: locale)
            } else {
                emptyMessage = AppLocalizedString.string("表示できるセッションがありません", locale: locale)
            }
        } else {
            emptyMessage = nil
        }

        var clearActions: [ClearAction] = []
        if isProjectFiltered {
            clearActions.append(.projectFilter)
        }
        if hasSessionSelection {
            clearActions.append(.sessionSelection)
        }

        return GridScopeSummary(
            title: title,
            countText: countText,
            isEmpty: isEmpty,
            emptyMessage: emptyMessage,
            clearActions: clearActions
        )
    }

    static func make(
        projects: [Project],
        filterProjectID: ProjectID?,
        visibleCount: Int,
        hasSessionSelection: Bool,
        locale: Locale = Locale(identifier: "ja")
    ) -> GridScopeSummary {
        let matched = filterProjectID.flatMap { id in
            projects.first(where: { $0.id == id })
        }
        return make(
            isProjectFiltered: matched != nil,
            projectName: matched?.name,
            visibleCount: visibleCount,
            hasSessionSelection: hasSessionSelection,
            locale: locale
        )
    }
}
