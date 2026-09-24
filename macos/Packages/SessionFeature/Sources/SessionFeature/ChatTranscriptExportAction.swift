import AppKit
import Foundation
import UniformTypeIdentifiers
import AgentDomain
import DesignSystem

/// `/export` 相当。選択中のチャットセッションの会話を Markdown で書き出す。
///
/// `/export` は Claude Code の対話 TUI 専用でヘッドレスのセッションへは送れないため、
/// Phlox が自分で持っている transcript から同じものを作る。
@MainActor
public enum ChatTranscriptExportAction {
    static func markdown(for session: ChatSessionViewModel, exportedAt: Date = Date()) -> String {
        ChatTranscriptExporter.markdown(
            items: session.transcript,
            metadata: ChatTranscriptExportMetadata(
                sessionTitle: session.displayName,
                agentName: agentName(for: session.agentRef),
                workingDirectory: session.workspacePath.isEmpty ? nil : session.workspacePath,
                exportedAt: exportedAt
            ),
            options: ChatTranscriptExportOptions.stored()
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
    /// - Parameter showsOptions: 前段で書き出しの設定を選んでいない入口（メニューの ⇧⌘E）では、保存パネルに設定を出す（09 D9）。
    public static func save(session: ChatSessionViewModel, locale: Locale, showsOptions: Bool = false) {
        let exportedAt = Date()
        let panel = NSSavePanel()
        panel.title = AppLocalizedString.string("会話を書き出す", locale: locale)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = ChatTranscriptExporter.suggestedFileName(
            sessionTitle: session.displayName,
            exportedAt: exportedAt
        )
        let options = showsOptions ? ExportOptionsAccessory(locale: locale) : nil
        panel.accessoryView = options?.view
        guard panel.runModal() == .OK, let url = panel.url else { return }
        options?.store()
        let text = markdown(for: session, exportedAt: exportedAt)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            // 09 D10: 起きたことを言い切り、エラー文はそのまま等幅で出す。次の手は保存し直し（2 つ目のボタンの左に置く）。
            let chosen = DSDialogModal.run(
                .notice,
                title: AppLocalizedString.string("会話を書き出せませんでした", locale: locale),
                message: AppLocalizedString.string("選んだ場所に書き込めませんでした。", locale: locale),
                log: "\(url.path): \(error.localizedDescription)",
                buttons: [("別の場所に保存…", .normal), ("OK", .primary)],
                locale: locale
            )
            if chosen == 0 {
                save(session: session, locale: locale)
            }
        }
    }

    /// クリップボードへ Markdown をコピーする。
    public static func copyToPasteboard(session: ChatSessionViewModel) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: session), forType: .string)
    }
}

/// 保存パネルに添える書き出しの設定。会話ヘッダの書き出し（04 C6）と同じ値をアプリ全体で記憶する。
@MainActor
private final class ExportOptionsAccessory {
    let view: NSView
    private let boxes: [(key: String, button: NSButton)]

    init(locale: Locale) {
        let stored = ChatTranscriptExportOptions.stored()
        let items: [(String, String, Bool)] = [
            (ChatTranscriptExportOptions.includesReasoningKey, "推論を含める", stored.includesReasoning),
            (ChatTranscriptExportOptions.includesCommandOutputKey, "コマンド出力を含める", stored.includesCommandOutput),
            (ChatTranscriptExportOptions.includesTimestampsKey, "タイムスタンプを含める", stored.includesTimestamps),
        ]
        boxes = items.map { key, title, isOn in
            let button = NSButton(checkboxWithTitle: AppLocalizedString.string(title, locale: locale), target: nil, action: nil)
            button.state = isOn ? .on : .off
            return (key, button)
        }
        let stack = NSStackView(views: boxes.map(\.button))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        stack.frame.size = stack.fittingSize
        view = stack
    }

    func store() {
        for box in boxes {
            UserDefaults.standard.set(box.button.state == .on, forKey: box.key)
        }
    }
}
