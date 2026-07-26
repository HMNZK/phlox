import AppKit
import Foundation
import UniformTypeIdentifiers
import AgentDomain
import DashboardFeature
import SessionFeature

/// `/export` 相当。選択中のチャットセッションの会話を Markdown で書き出す。
///
/// `/export` は Claude Code の対話 TUI 専用でヘッドレスのセッションへは送れないため、
/// Phlox が自分で持っている transcript から同じものを作る。
@MainActor
enum ChatTranscriptExportAction {
    /// 選択中セッションがチャット（appServer）ならその ViewModel を返す。PTY セッションは対象外。
    static func selectedChatSession(dashboard: DashboardViewModel?, router: AppRouter?) -> ChatSessionViewModel? {
        guard let dashboard,
              let sessionID = router?.selectedSession,
              case .appServer(let chat) = dashboard.sessionNode(id: sessionID)
        else { return nil }
        return chat
    }

    static func markdown(for session: ChatSessionViewModel, exportedAt: Date = Date()) -> String {
        ChatTranscriptExporter.markdown(
            items: session.transcript,
            metadata: ChatTranscriptExportMetadata(
                sessionTitle: session.displayName,
                agentName: agentName(for: session.agentRef),
                workingDirectory: session.workspacePath.isEmpty ? nil : session.workspacePath,
                exportedAt: exportedAt
            )
        )
    }

    /// 書き出しの見出しに載せるエージェント名。カスタムエージェントは登録 ID をそのまま使う。
    private static func agentName(for ref: AgentRef) -> String {
        switch ref {
        case .builtin(let kind): return kind.displayName
        case .custom(let id): return id
        }
    }

    /// 保存ダイアログを出して Markdown を書き出す。
    static func save(session: ChatSessionViewModel) {
        let exportedAt = Date()
        let panel = NSSavePanel()
        panel.title = "会話を書き出す"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = ChatTranscriptExporter.suggestedFileName(
            sessionTitle: session.displayName,
            exportedAt: exportedAt
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = markdown(for: session, exportedAt: exportedAt)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "書き出せませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// クリップボードへ Markdown をコピーする。
    static func copyToPasteboard(session: ChatSessionViewModel) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: session), forType: .string)
    }
}
