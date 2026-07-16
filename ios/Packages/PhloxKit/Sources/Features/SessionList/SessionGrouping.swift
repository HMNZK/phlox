import Foundation
import PhloxCore

/// プロジェクト単位にまとめたセッション群（DisclosureGroup 1 件分）。
public struct ProjectGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let sessions: [Session]

    public init(id: String, title: String, sessions: [Session]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }
}

/// セッション一覧のプロジェクト単位グルーピング（View 非依存の純ロジック）。
public enum SessionGrouping {
    /// `projectName == nil` のセッションを入れる末尾グループの表示名（デスクトップ版「その他」に倣う）。
    public static let otherGroupTitle = "その他"

    private static let otherGroupID = "__other__"

    /// 入力順を保ちつつプロジェクトごとに 1 グループへ集約する。未所属（`projectName == nil`）は末尾の既定グループ。
    public static func grouped(from sessions: [Session]) -> [ProjectGroup] {
        var namedGroups: [ProjectGroup] = []
        var namedIndexByKey: [String: Int] = [:]
        var otherSessions: [Session] = []

        for session in sessions {
            guard let projectName = session.projectName else {
                otherSessions.append(session)
                continue
            }
            let key = session.projectId ?? projectName
            if let index = namedIndexByKey[key] {
                let existing = namedGroups[index]
                namedGroups[index] = ProjectGroup(
                    id: existing.id,
                    title: existing.title,
                    sessions: existing.sessions + [session]
                )
            } else {
                namedIndexByKey[key] = namedGroups.count
                namedGroups.append(ProjectGroup(id: key, title: projectName, sessions: [session]))
            }
        }

        var result = namedGroups
        if !otherSessions.isEmpty {
            result.append(ProjectGroup(id: otherGroupID, title: otherGroupTitle, sessions: otherSessions))
        }
        return result
    }
}
