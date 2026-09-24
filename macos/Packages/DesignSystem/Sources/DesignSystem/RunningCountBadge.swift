import SwiftUI

/// プロジェクト行右端の「n 実行中」。無彩色の文字だけ。
public struct RunningCountBadge: View {
    public let count: Int
    public let nestedOrchestrationCount: Int
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @Environment(\.locale) private var locale

    public init(count: Int, nestedOrchestrationCount: Int = 0) {
        self.count = count
        self.nestedOrchestrationCount = nestedOrchestrationCount
    }

    public var body: some View {
        if count > 0 {
            Text(Self.label(count: count, nested: nestedOrchestrationCount, japanese: isJapanese))
                .font(DSFont.meta)
                .foregroundStyle(DSColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var isJapanese: Bool { locale.language.languageCode?.identifier == "ja" }

    static func label(count: Int, nested: Int, japanese: Bool) -> String {
        switch (japanese, nested > 0) {
        case (true, false): "\(count) 実行中"
        case (true, true): "\(count) 実行中（内部 \(nested)）"
        case (false, false): "\(count) running"
        case (false, true): "\(count) running (\(nested) internal)"
        }
    }
}
