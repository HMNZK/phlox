/// detail 領域へ表示する内容。
public enum StartAreaContent: Equatable, Sendable {
    case projectOnboarding
    case sessionContent
    case newChat
}

/// セッション未選択時は、選択プロジェクトの新規チャット画面へ進む。
public enum StartAreaPolicy {
    public static func content(hasSelectedSession: Bool, hasProjects: Bool = true) -> StartAreaContent {
        guard hasProjects else { return .projectOnboarding }
        return hasSelectedSession ? .sessionContent : .newChat
    }
}
