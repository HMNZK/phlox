import Foundation
import PhloxCore
import SwiftUI
import DesignSystemIOS

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// メッセージのコピーボタンがクリップボードへ入れる文字列の生成（純関数）。
/// View（task-8）はバブルのコピーボタンからこれを呼ぶ。
/// 契約は Tests/FeaturesTests/ChatSurfaceAcceptanceTests.swift。
public enum ChatMessageCopyText {
    /// メッセージ種別ごとのコピー文字列。
    /// - user/agent/reasoning/subAgent: text 全文
    /// - command: `$ <command>\n<output>`（command が nil なら output のみ）
    /// - error: message
    /// - fileChange: `<path>\n<diff>` を空行区切りで連結
    /// 空文字列になる場合は nil（コピーボタンを出さない）。
    public static func copyText(for message: ChatMessage) -> String? {
        let raw: String
        switch message {
        case let .user(_, text), let .agent(_, text), let .reasoning(_, text), let .subAgent(_, text):
            raw = text
        case let .command(_, command, output):
            if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                raw = "$ \(command)\n\(output)"
            } else {
                raw = output
            }
        case let .error(_, message):
            raw = message
        case let .fileChange(_, changes):
            raw = changes.map { "\($0.path)\n\($0.diff)" }.joined(separator: "\n\n")
        case let .userQuestion(_, _, questions, _, _):
            raw = questions.map(\.question).joined(separator: "\n")
        }
        return normalizedCopyText(raw)
    }

    /// 空・空白のみは nil（コピーボタン非表示）。
    public static func normalizedCopyText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    /// グループのコピー対象になる1件分のテキスト。空文字は対象外。
    /// 可否判定と文字列生成の両方がこの1本を通るので、定義が食い違わない。
    static func commandGroupCopyablePart(for message: ChatMessage) -> String? {
        guard let text = copyText(for: message), !text.isEmpty else { return nil }
        return text
    }

    /// グループのコピーボタンを表示するかを、最初のコピー可能な message で打ち切って判定する。
    public static func commandGroupHasCopyableText(_ messages: [ChatMessage]) -> Bool {
        messages.contains { commandGroupCopyablePart(for: $0) != nil }
    }

    /// グループ内のコピー可能な message を元の順序で空行区切りに連結する。
    /// この関数はコピーボタンが押された時だけ呼ぶ。
    public static func commandGroupCopyText(_ messages: [ChatMessage]) -> String? {
        let parts = messages.compactMap(commandGroupCopyablePart(for:))
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }
}

/// チャットメッセージ用コピーボタン（`doc.on.doc` → `checkmark` トグル）。
public struct ChatMessageCopyButton: View {
    struct DeferredText {
        let provider: () -> String?

        func value() -> String? {
            provider()
        }
    }

    private let deferredText: DeferredText
    @State private var copied = false

    public init(text: String) {
        deferredText = DeferredText(provider: { text })
    }

    public init(textProvider: @escaping () -> String?) {
        deferredText = DeferredText(provider: textProvider)
    }

    public var body: some View {
        Button(action: copyToPasteboard) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(DSFont.captionStrong)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "コピーしました" : "コピー")
    }

    private func copyToPasteboard() {
        guard let text = deferredText.value() else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
