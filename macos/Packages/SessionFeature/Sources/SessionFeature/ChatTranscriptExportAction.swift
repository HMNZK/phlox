import AppKit
import SwiftUI
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
    /// - Parameter showsOptions: 前段で書き出しの設定を選んでいない入口（メニューの ⇧⌘E）では、先に設定を選ぶ画面を出す（09 D9）。
    public static func save(session: ChatSessionViewModel, locale: Locale, showsOptions: Bool = false) {
        if showsOptions {
            let choice = ExportOptionsChoice()
            let chosen = DSDialogModal.run(
                .recoverable,
                title: AppLocalizedString.string("会話を Markdown で書き出す", locale: locale),
                message: AppLocalizedString.string("推論・コマンド出力・タイムスタンプを含めるかを選び、次の画面で保存先を選びます。", locale: locale),
                content: AnyView(ExportOptionsForm(choice: choice)),
                buttons: [("キャンセル", .normal), ("書き出す…", .primary)],
                locale: locale
            )
            guard chosen == 1 else { return }
            choice.store()
        }
        let exportedAt = Date()
        let panel = NSSavePanel()
        panel.title = AppLocalizedString.string("会話を書き出す", locale: locale)
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

/// 書き出しの前段（09 D9）で選ぶ設定。会話ヘッダの書き出し（04 C6）と同じ値をアプリ全体で記憶し、「書き出す…」を押したときだけ保存する。
@MainActor
private final class ExportOptionsChoice {
    var options = ChatTranscriptExportOptions.stored()

    func store() {
        let defaults = UserDefaults.standard
        defaults.set(options.includesReasoning, forKey: ChatTranscriptExportOptions.includesReasoningKey)
        defaults.set(options.includesCommandOutput, forKey: ChatTranscriptExportOptions.includesCommandOutputKey)
        defaults.set(options.includesTimestamps, forKey: ChatTranscriptExportOptions.includesTimestampsKey)
    }
}

private struct ExportOptionsForm: View {
    let choice: ExportOptionsChoice
    @State private var options: ChatTranscriptExportOptions

    init(choice: ExportOptionsChoice) {
        self.choice = choice
        _options = State(initialValue: choice.options)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("推論を含める", isOn: $options.includesReasoning)
            Toggle("コマンド出力を含める", isOn: $options.includesCommandOutput)
            Toggle("タイムスタンプを含める", isOn: $options.includesTimestamps)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: options) { _, newValue in choice.options = newValue }
    }
}
