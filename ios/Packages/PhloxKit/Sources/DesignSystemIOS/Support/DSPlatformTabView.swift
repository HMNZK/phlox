import SwiftUI

/// OS 標準のタブ表示。iOS 26 は Liquid Glass と下部アクセサリ、iOS 18 は標準バーと下端挿入を使う。
@available(iOS 18.0, macOS 15.0, *)
public struct DSPlatformTabView<Selection: Hashable, Tabs: TabContent, Accessory: View>: View
where Tabs.TabValue == Selection? {
    @Binding private var selection: Selection?
    private let tabs: Tabs
    private let accessory: Accessory
    private let accessoryEnabled: Bool

    public init(
        selection: Binding<Selection?>,
        accessoryEnabled: Bool = true,
        @TabContentBuilder<Selection?> tabs: () -> Tabs,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _selection = selection
        self.accessoryEnabled = accessoryEnabled
        self.tabs = tabs()
        self.accessory = accessory()
    }

    @ViewBuilder
    public var body: some View {
#if os(iOS)
        if #available(iOS 26, *) {
            if accessoryEnabled {
                iOS26Tabs
                    .tabViewBottomAccessory {
                        accessory
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassSurface(.waitingBar)
                    }
                    .tabBarMinimizeBehavior(.onScrollDown)
            } else {
                iOS26Tabs
                    .tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            iOS18Tabs
        }
#else
        iOS18Tabs
#endif
    }

    private var iOS26Tabs: some View {
        TabView(selection: $selection) {
            tabs
            Tab(value: nil as Selection?, role: .search) {
                Color.clear
            } label: {
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("新規チャット")
            }
        }
        .tint(IOSColor.text.primary)
    }

    private var iOS18Tabs: some View {
        TabView(selection: $selection) {
            tabs
        }
        .tint(IOSColor.text.primary)
    }
}

/// iOS 18 ではタブ内容内にアクセサリを挿入し、標準タブバーの下端を動かさない。
@available(iOS 18.0, macOS 15.0, *)
public struct DSPlatformTabContent<Content: View, Accessory: View>: View {
    private let content: Content
    private let accessory: Accessory
    private let accessoryEnabled: Bool

    public init(
        accessoryEnabled: Bool,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.accessoryEnabled = accessoryEnabled
        self.content = content()
        self.accessory = accessory()
    }

    @ViewBuilder
    public var body: some View {
#if os(iOS)
        if #available(iOS 26, *) {
            content
        } else if accessoryEnabled {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                accessory
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassSurface(.waitingBar)
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

/// iOS 18 の一覧見出しに置く新規チャット操作。iOS 26 では独立したタブ操作に委ねる。
public struct DSLegacyNewChatButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
#if os(iOS)
        if #available(iOS 26, *) {
            EmptyView()
        } else {
            Button(action: action) {
                Image(systemName: "square.and.pencil")
                    .font(DSFont.iconFAB)
                    .foregroundStyle(IOSColor.text.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新規チャット")
        }
#else
        EmptyView()
#endif
    }
}
