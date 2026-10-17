import Foundation

enum SessionDetailCopy {
    static let inputPlaceholder = "やりたいことを入力"
    static let questionInputPlaceholder = "回答を入力"
    private static let startedPrefix = "開始 "

    static func inputPlaceholder(isAnsweringSelectionlessQuestion: Bool) -> String {
        isAnsweringSelectionlessQuestion ? questionInputPlaceholder : inputPlaceholder
    }

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
