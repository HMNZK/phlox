import Foundation
import DesignSystem

public enum WorktreeStartPoint: Hashable, Sendable {
    case head
    case localBranch(String)
    case remoteBranch(String)
    case tag(String)
    case commit(String)

    var revision: String {
        switch self {
        case .head: "HEAD"
        case .localBranch(let name): "refs/heads/" + name
        case .remoteBranch(let name): "refs/remotes/" + name
        case .tag(let name): "refs/tags/" + name
        case .commit(let id): id
        }
    }

    var sectionKey: String? {
        switch self {
        case .head: nil
        case .localBranch: "ローカルのブランチ"
        case .remoteBranch: "リモートのブランチ"
        case .tag: "タグ"
        case .commit: "最近のコミット"
        }
    }

    func title(locale: Locale = .current, bundle: Bundle = .main) -> String {
        switch self {
        case .head: AppLocalizedString.string("今の位置（HEAD）", locale: locale, bundle: bundle)
        case .localBranch(let name), .remoteBranch(let name), .tag(let name): name
        case .commit(let id): String(format: AppLocalizedString.string("コミット %@", locale: locale, bundle: bundle), String(id.prefix(8)))
        }
    }

    static func isCommitID(_ query: String) -> Bool {
        query.count >= 4 && query.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
}

struct WorktreeStartPointItem: Hashable, Sendable {
    let point: WorktreeStartPoint
    var summary: String? = nil
}

struct WorktreeStartPointError: LocalizedError {
    let point: WorktreeStartPoint

    var errorDescription: String? {
        String(format: AppLocalizedString.string("起点「%@」をコミットとして解決できないため、開始しませんでした。起点を選び直してください。", locale: .current), point.title())
    }
}
