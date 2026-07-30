import SwiftUI

/// チャット内のコード表示を包む共通の器。
/// 見出しの内容や展開状態は呼び出し側に委ね、カード自身は装飾と配置だけを担当する。
public struct DSChatCodeCard<Header: View, Content: View>: View {
    private nonisolated(unsafe) let header: Header
    private nonisolated(unsafe) let content: Content

    public nonisolated init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    public nonisolated var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            header
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .frame(minHeight: DSTouch.minSize, alignment: .leading)

            content
        }
        .background(DSColor.chatCard)
        .clipShape(cardShape)
        .overlay(cardShape.strokeBorder(DSColor.border, lineWidth: DSChatCodeCardMetrics.borderWidth))
    }

    private nonisolated var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSChatCodeCardMetrics.cornerRadius, style: .continuous)
    }
}

/// `DSChatCodeCard` の寸法を一元管理する。
public enum DSChatCodeCardMetrics {
    public static let cornerRadius: CGFloat = DSRadius.card
    public static let borderWidth: CGFloat = 1
}
