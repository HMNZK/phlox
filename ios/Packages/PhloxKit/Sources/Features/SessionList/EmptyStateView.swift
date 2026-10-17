import DesignSystemIOS
import SwiftUI

public enum EmptyStateCopy {
    public static let title = "セッションがありません"
    public static let subtitle = "Mac でエージェントを動かすと、ここにセッションが並びます。iPhone から始めるときは「新規チャット」を押してください。"
    public static let projectNote = "プロジェクトの欄は、セッションが 1 つ以上あるプロジェクトだけが出ます。"
    public static let ctaTitle = "新規チャット"
}

/// セッションが 0 件のときの一覧。
public struct EmptyStateView: View {
    let onCreate: () -> Void

    public init(onCreate: @escaping () -> Void) {
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "square.and.pencil")
                .font(DSFont.title2)
                .foregroundStyle(IOSColor.text.secondary)
                .frame(width: 72, height: 72)
                .background(IOSColor.bg.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(EmptyStateCopy.title)
                .font(DSFont.title2.weight(.bold))
                .foregroundStyle(IOSColor.text.primary)
                .multilineTextAlignment(.center)
                .padding(.top, DSSpacing.s)
            Text(EmptyStateCopy.subtitle)
                .font(DSFont.body)
                .foregroundStyle(IOSColor.text.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
            Text(EmptyStateCopy.projectNote)
                .font(DSFont.auxiliary)
                .foregroundStyle(IOSColor.text.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330)
            Button(action: onCreate) {
                Label(EmptyStateCopy.ctaTitle, systemImage: "square.and.pencil")
                    .font(DSFont.headline.weight(.semibold))
                    .foregroundStyle(IOSColor.accentOnFill)
                    .padding(.horizontal, DSSpacing.xl)
                    .frame(minHeight: 50)
                    .background(IOSColor.accent, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(EmptyStateCopy.ctaTitle)
            .padding(.top, 17)
        }
        .padding(.top, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(IOSColor.bg.base)
    }
}

#if DEBUG
#Preview {
    EmptyStateView(onCreate: {})
}
#endif
