import Foundation
import AgentDomain

enum FileTabOpening {
    static func projectRelativeChangePath(_ path: String, workingDirectory: String) async -> String? {
        let service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: workingDirectory, isDirectory: true))
        guard let gitRoot = await service.resolvedRepositoryRootPath() else { return nil }
        let url = URL(fileURLWithPath: gitRoot, isDirectory: true).appendingPathComponent(path)
        return relativePath(of: url, under: await root(for: workingDirectory))
    }

    static func root(for workingDirectory: String) async -> String {
        return URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func relativePath(of url: URL, under rootPath: String) -> String? {
        // 親だけ解決してファイルのリンク名を保つ。包含確認は読み書きの共通経路でも行う。
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        let file = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard file.hasPrefix(prefix) else { return nil }
        return String(file.dropFirst(prefix.count))
    }
}

extension FileTabDocuments {
    /// 要求時の作業場所とルートで文書を作り、操作中の区画へ開く。
    @discardableResult
    func openFileTab(
        projectID: ProjectID,
        root: String,
        relativePath: String,
        split: Bool = false,
        router: AppRouter,
        requestedWorkingDirectory: String,
        currentWorkingDirectory: String?
    ) -> Bool {
        guard requestedWorkingDirectory == currentWorkingDirectory,
              !FileTabDocumentRegistry.shared.isChangingProject(projectID) else { return false }
        let root = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        let document = document(for: projectID, path: relativePath, root: root)
        guard document.root == root, !document.invalidated else { return false }
        router.selectedProjectID = projectID
        router.viewMode = .single
        router.tabs.updateLayout(for: projectID) {
            if split {
                if !$0.items.contains(.file(relativePath)) { $0.items.append(.file(relativePath)) }
                $0.splitRight(.file(relativePath))
            }
            else { $0.open(.file(relativePath)) }
        }
        return true
    }
}
