import SwiftUI

public struct RunningCountBadge: View {
    public let count: Int
    public let nestedOrchestrationCount: Int
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    public init(count: Int, nestedOrchestrationCount: Int = 0) {
        self.count = count
        self.nestedOrchestrationCount = nestedOrchestrationCount
    }

    public var body: some View {
        if count > 0 {
            HStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(DSColor.statusRunning)
                    .frame(width: 6, height: 6)
                Text(labelText)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.statusRunning)
            }
            .fixedSize()
            .accessibilityLabel(accessibilityText)
            .help(nestedOrchestrationCount > 0 ? nestedHelpText : "")
        }
    }

    private var labelText: String {
        if nestedOrchestrationCount > 0 {
            return "\(count) running (\(nestedOrchestrationCount) nested)"
        }
        return "\(count) running"
    }

    private var accessibilityText: String {
        if nestedOrchestrationCount > 0 {
            return "\(count) running, \(nestedOrchestrationCount) nested orchestration"
        }
        return "\(count) running"
    }

    private var nestedHelpText: String {
        "\(nestedOrchestrationCount) nested orchestration session\(nestedOrchestrationCount == 1 ? "" : "s") running"
    }
}
