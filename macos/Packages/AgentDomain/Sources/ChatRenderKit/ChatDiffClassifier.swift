import Foundation

public enum ChatDiffLineKind: Equatable, Sendable {
    case fileHeader
    case hunk
    case addition
    case deletion
    case context
}

public struct ChatDiffLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let kind: ChatDiffLineKind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(
        id: Int,
        text: String,
        kind: ChatDiffLineKind,
        oldLineNumber: Int?,
        newLineNumber: Int?
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }

    public var isDisplayable: Bool {
        kind != .fileHeader && text != "\\ No newline at end of file"
    }

    public var displayLineNumber: Int? {
        guard isDisplayable else { return nil }
        return switch kind {
        case .deletion: oldLineNumber
        case .addition, .context: newLineNumber
        case .fileHeader, .hunk: nil
        }
    }
}

public enum ChatDiffClassifier {
    public static func classify(_ diff: String) -> [ChatDiffLine] {
        var oldLineNumber: Int?
        var newLineNumber: Int?

        return diff.components(separatedBy: .newlines).enumerated().map { index, line in
            let lineKind = kind(for: line)
            if lineKind == .hunk {
                if let hunk = hunkStartNumbers(in: line) {
                    oldLineNumber = hunk.old
                    newLineNumber = hunk.new
                } else {
                    oldLineNumber = nil
                    newLineNumber = nil
                }
            }

            let result = ChatDiffLine(
                id: index,
                text: line,
                kind: lineKind,
                oldLineNumber: lineKind == .deletion ? oldLineNumber : nil,
                newLineNumber: lineKind == .addition || (lineKind == .context && line != "\\ No newline at end of file") ? newLineNumber : nil
            )

            guard result.isDisplayable else { return result }

            switch lineKind {
            case .deletion:
                advanceLineNumber(.old, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .addition:
                advanceLineNumber(.new, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .context:
                advanceLineNumber(.old, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
                advanceLineNumber(.new, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .fileHeader, .hunk:
                break
            }
            return result
        }
    }

    /// 加算不能な採番は推測せず、以降の old/new 両方の採番を停止する。
    private enum LineNumberSide {
        case old
        case new
    }

    private static func advanceLineNumber(
        _ side: LineNumberSide,
        oldLineNumber: inout Int?,
        newLineNumber: inout Int?
    ) {
        let currentLineNumber = switch side {
        case .old: oldLineNumber
        case .new: newLineNumber
        }
        guard let currentLineNumber else { return }
        let (next, overflow) = currentLineNumber.addingReportingOverflow(1)
        if overflow {
            oldLineNumber = nil
            newLineNumber = nil
        } else {
            switch side {
            case .old: oldLineNumber = next
            case .new: newLineNumber = next
            }
        }
    }

    private static func kind(for line: String) -> ChatDiffLineKind {
        if line.hasPrefix("@@") {
            return .hunk
        }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git") || line.hasPrefix("index ") {
            return .fileHeader
        }
        if line.hasPrefix("+") {
            return .addition
        }
        if line.hasPrefix("-") {
            return .deletion
        }
        return .context
    }

    private static func hunkStartNumbers(in line: String) -> (old: Int, new: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
              let old = hunkStart(in: parts[1], marker: "-"),
              let new = hunkStart(in: parts[2], marker: "+") else {
            return nil
        }
        return (old, new)
    }

    private static func hunkStart(in part: Substring, marker: Character) -> Int? {
        guard part.first == marker else { return nil }
        let digits = part.dropFirst().prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
