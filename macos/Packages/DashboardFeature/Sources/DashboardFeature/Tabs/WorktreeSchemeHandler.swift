import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor final class WorktreeSchemeHandler: NSObject, WKURLSchemeHandler {
    private let service: WorkingTreeService
    private let documentPath: String
    private var draft: String
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(root: String, documentPath: String, draft: String) {
        service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root, isDirectory: true), fixedRoot: true)
        self.documentPath = documentPath
        self.draft = draft
    }

    func updateDraft(_ draft: String) {
        self.draft = draft
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        let snapshot = draft
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                guard urlSchemeTask.request.httpMethod == "GET",
                      let url = urlSchemeTask.request.url,
                      let path = WorktreeURL.relativePath(url) else { throw URLError(.badURL) }
                let data: Data
                if path == documentPath {
                    guard await service.absolutePath(path) != nil else { throw URLError(.noPermissionsToReadFile) }
                    guard snapshot.utf8.count <= WorkingTreeService.maximumHTMLResourceSize else {
                        throw URLError(.dataLengthExceedsMaximum)
                    }
                    data = Data(snapshot.utf8)
                } else {
                    data = try await service.resourceData(path)
                }
                let mime = UTType(filenameExtension: (path as NSString).pathExtension.lowercased())?.preferredMIMEType ?? "application/octet-stream"
                // 同じ URL の CSS や画像も、再読込・保存時には最新の内容を配信する。
                let contentType = mime.hasPrefix("text/") ? mime + "; charset=utf-8" : mime
                guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                    headerFields: ["Content-Type": contentType, "Cache-Control": "no-store"]) else {
                    throw URLError(.badServerResponse)
                }
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didReceive(response)
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didReceive(data)
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didFailWithError(error)
            }
            tasks[id] = nil
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    func stopAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
}
