import SwiftUI
import DesignSystem

/// セッション詳細のシステムナビゲーションバーとタイトル表示。
/// iOS 26 と iOS 18 のバー描画差は共通部品内に閉じ込める。
public struct DSSessionNavigationChrome<Menu: View>: ViewModifier {
    private let title: String
    private let subtitle: Text?
    private let displayState: SessionDisplayState?
    private let menu: Menu

    public init(
        title: String,
        subtitle: Text?,
        displayState: SessionDisplayState? = nil,
        @ViewBuilder menu: () -> Menu
    ) {
        self.title = title
        self.subtitle = subtitle
        self.displayState = displayState
        self.menu = menu()
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if #unavailable(iOS 26) {
                    IOSColor.bg.separator
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(DSFont.sessionDetailTitle)
                            .foregroundStyle(IOSColor.text.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if subtitle != nil || displayState?.showsActivityIndicator == true {
                            HStack(spacing: DSSpacing.xs) {
                                if let displayState, displayState.showsActivityIndicator {
                                    SessionActivityIndicator(state: displayState)
                                }
                                if let subtitle {
                                    subtitle
                                        .font(DSFont.sessionDetailSubtitle)
                                        // ナビの副題だけ拡大を抑え、本文の Dynamic Type は維持する。
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityElement(children: .combine)
                }
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarTrailing) { trailingMenu }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { trailingMenu }
                }
            }
        #else
        content.navigationTitle(title)
        #endif
    }

    @ViewBuilder
    private var trailingMenu: some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            menu
                .buttonStyle(.plain)
                .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                .glassSurface(.roundButton)
        } else {
            menu
                .buttonStyle(.plain)
                .frame(width: DSTouch.minSize, height: DSTouch.minSize)
        }
        #else
        menu
        #endif
    }

}
