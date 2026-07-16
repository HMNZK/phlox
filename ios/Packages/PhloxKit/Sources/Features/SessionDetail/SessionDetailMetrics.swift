import CoreGraphics
import Foundation
import AgentDomain
import DesignSystemIOS

/// カンプ③ セッション詳細の寸法・文言（テスト可能な契約）。
enum SessionDetailMetrics {
    static let headerAgentBadgeSize: CGFloat = 48
    static let headerAgentBadgeCornerRadius: CGFloat = 12
    static let outputCollapseLineLimit = 12

    static func campAbbreviation(for kind: AgentKind) -> String {
        DSSessionRow.campAbbreviation(for: kind)
    }

    static func outputNeedsToggle(text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).count > outputCollapseLineLimit
    }

    /// 折りたたみ時は長文を非表示。短文は常に表示する。
    static func displayedOutput(text: String, isExpanded: Bool) -> String? {
        guard outputNeedsToggle(text: text) else { return text }
        return isExpanded ? text : nil
    }
}

enum SessionDetailCopy {
    static let inputPlaceholder = "回答を入力…"
    static let outputSectionTitle = "出力"
    private static let startedPrefix = "開始 "

    static func headerMetaLine(
        agentDisplayName: String,
        startedAt: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ja_JP")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return "\(agentDisplayName) · \(startedPrefix)\(formatter.string(from: startedAt))"
    }
}
