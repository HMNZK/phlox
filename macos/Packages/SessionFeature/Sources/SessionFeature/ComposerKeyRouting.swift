import AppKit

// task-4 契約の PM スタブ。API 表面は受け入れテスト
// ComposerKeyRoutingAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-4.md（既存 SubmitAwareTextView.keyDown の挙動を意味を変えず移す）

/// composer のキーイベントの行き先。
public enum ComposerKeyAction: Equatable {
    case undo
    case redo
    case paste
    case submit
    case insertNewline
    case escape
    case passToSystem
    // サジェスト表示中のみ発生（task-7 契約。受け入れテスト ComposerSuggestionAcceptance が凍結）
    case moveSuggestionUp
    case moveSuggestionDown
    case acceptSuggestion
    case dismissSuggestions
}

/// composer キーイベントの純関数ルーティング（keyDown から呼ばれる）。
public enum ComposerKeyRouting {
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    public static func action(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isComposing: Bool,
        suggestionsVisible: Bool = false
    ) -> ComposerKeyAction {
        let modifiers = modifierFlags.intersection(relevantModifiers)

        if suggestionsVisible, !isComposing {
            if modifiers.isEmpty {
                switch keyCode {
                case 125:
                    return .moveSuggestionDown
                case 126:
                    return .moveSuggestionUp
                case 48, 36, 76:
                    return .acceptSuggestion
                case 53:
                    return .dismissSuggestions
                default:
                    break
                }
            }
        }

        if keyCode == 6 {
            if isComposing {
                return .passToSystem
            }
            switch modifiers {
            case [.command], [.control]:
                return .undo
            case [.command, .shift], [.control, .shift]:
                return .redo
            default:
                return .passToSystem
            }
        }

        if keyCode == 9 {
            if isComposing {
                return .passToSystem
            }
            if modifiers == [.command] {
                return .paste
            }
            return .passToSystem
        }

        if keyCode == 36 || keyCode == 76 {
            if modifiers.contains(.command) {
                return .submit
            }
            if modifiers.contains(.shift) {
                return .insertNewline
            }
            if isComposing {
                return .passToSystem
            }
            if modifiers.isEmpty {
                return .submit
            }
            return .passToSystem
        }

        if keyCode == 53 {
            if isComposing {
                return .passToSystem
            }
            return .escape
        }

        return .passToSystem
    }
}
