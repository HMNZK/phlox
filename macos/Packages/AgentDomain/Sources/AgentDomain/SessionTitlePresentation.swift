import Foundation

public struct SessionTitlePresentation: Equatable, Sendable {
    public let primary: String
    public let secondary: String?
    public let fullTitle: String
    public let helpText: String
    public let accessibilityValue: String

    public init(
        state: SessionTitleState,
        fallback: String,
        workspacePath: String
    ) {
        let primary = state.effectiveName(fallback: fallback)
        self.primary = primary
        if let flowerName = state.flowerName, flowerName != primary {
            self.secondary = flowerName
        } else {
            self.secondary = nil
        }
        if state.source == .derived, let fullDerivedTitle = state.fullDerivedTitle {
            self.fullTitle = fullDerivedTitle
        } else {
            self.fullTitle = primary
        }
        var helpLines = [fullTitle]
        if let flowerName = state.flowerName {
            helpLines.append("花名: \(flowerName)")
        }
        helpLines.append("作業場所: \(workspacePath)")
        self.helpText = helpLines.joined(separator: "\n")
        self.accessibilityValue = fullTitle
    }
}
