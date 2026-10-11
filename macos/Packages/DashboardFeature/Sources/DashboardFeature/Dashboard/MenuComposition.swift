/// 「ファイル」メニューの新規項目グループ。列挙順が実際の表示順。
public enum FileMenuItem: String, CaseIterable, Hashable, Sendable {
    case newChat
    case newTab
    case openFile
    case addProject
    case divider
    case exportConversation
    case copyConversation
}

/// プロジェクト行の「⋯」と右クリックで共有するメニュー項目。
public enum ProjectRowMenuItem: String, CaseIterable, Hashable, Sendable {
    case newChat
    case rename
    case delete
}
