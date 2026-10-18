import SwiftUI

/// チャット内のコード表示を包む共通の器。
/// 見出しの内容や展開状態は呼び出し側に委ね、カード自身は装飾と配置だけを担当する。
public struct DSChatCodeCard<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content
    private let isRunning: Bool
    private let showsDivider: Bool

    public init(
        isRunning: Bool = false,
        showsDivider: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
        self.isRunning = isRunning
        self.showsDivider = showsDivider
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            header
                .padding(.horizontal, DSSpacing.m)
                .frame(minHeight: DSChatCodeCardMetrics.headerHeight, alignment: .leading)

            if showsDivider {
                Rectangle()
                    .fill(DSColor.separator)
                    .frame(height: DSChatCodeCardMetrics.borderWidth)
            }

            content
        }
        .background(DSColor.chatCard)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(
                isRunning ? DSColor.textSecondary : DSColor.border,
                lineWidth: isRunning ? DSChatCodeCardMetrics.runningBorderWidth : DSChatCodeCardMetrics.borderWidth
            )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSChatCodeCardMetrics.cornerRadius, style: .continuous)
    }
}

/// `DSChatCodeCard` の寸法を一元管理する。
public enum DSChatCodeCardMetrics {
    public static let cornerRadius: CGFloat = DSRadius.m
    public static let borderWidth: CGFloat = 1
    public static let runningBorderWidth: CGFloat = 1.5
    public static let headerHeight: CGFloat = DSTouch.minSize
}
