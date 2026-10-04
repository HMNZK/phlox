import SwiftUI
import ChatRenderKit
import DesignSystem

/// 字句の意味を既存トークンへ割り当てる。入力欄では前景色だけを使う。
public enum CodeSyntaxColor {
    public static func color(for kind: ChatCodeTokenKind, chat: Bool = false) -> Color {
        switch kind {
        case .keyword, .command, .operator, .tag, .structure, .selector:
            DSColor.codeSyntaxKeyword
        case .string, .variable, .link, .pattern:
            DSColor.codeSyntaxString
        case .number, .option, .subcommand, .attribute, .key, .section, .property, .date, .delimiter:
            DSColor.codeSyntaxNumber
        case .comment, .diffHeader, .annotation:
            DSColor.codeSyntaxComment
        case .diffAdded:
            DSColor.diffAdded
        case .diffRemoved:
            DSColor.diffRemoved
        case .diffHunk:
            DSColor.codeSyntaxKeyword
        case .plain:
            chat ? DSColor.chatTextPrimary : DSColor.textPrimary
        case .type:
            chat ? DSColor.attentionInk(.question) : DSColor.textPrimary
        case .member:
            chat ? DSColor.codeSyntaxNumber : DSColor.textPrimary
        case .call:
            chat ? DSColor.accentInk : DSColor.textPrimary
        }
    }
}
