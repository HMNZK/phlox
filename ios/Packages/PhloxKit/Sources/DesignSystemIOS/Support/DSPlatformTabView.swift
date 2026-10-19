import SwiftUI
#if os(iOS)
import UIKit
#endif

/// OS 標準のタブ表示。iOS 26 は Liquid Glass と下部アクセサリ、iOS 18 は標準バーと下端挿入を使う。
@available(iOS 18.0, macOS 15.0, *)
public struct DSPlatformTabView<Selection: Hashable, Tabs: TabContent, Accessory: View>: View
where Tabs.TabValue == Selection {
    @Binding private var selection: Selection
    private let actionValue: Selection
    private let tabs: Tabs
    private let accessory: Accessory
    private let accessoryEnabled: Bool
    private let onActionTabAppear: () -> Void

    public init(
        selection: Binding<Selection>,
        actionValue: Selection,
        accessoryEnabled: Bool = true,
        onActionTabAppear: @escaping () -> Void = {},
        @TabContentBuilder<Selection> tabs: () -> Tabs,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _selection = selection
        self.actionValue = actionValue
        self.accessoryEnabled = accessoryEnabled
        self.onActionTabAppear = onActionTabAppear
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
            Tab(value: actionValue, role: .search) {
                DSViewDidAppearObserver(role: "action", onAppear: onActionTabAppear)
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

/// iOS 18 と自然高さが必要な内容はタブ内に挿入し、標準タブバーの下端を動かさない。
@available(iOS 18.0, macOS 15.0, *)
public struct DSPlatformTabContent<Content: View, Accessory: View>: View {
    private let content: Content
    private let accessory: Accessory
    private let accessoryEnabled: Bool
    private let usesNativeAccessory: Bool

    public init(
        accessoryEnabled: Bool,
        usesNativeAccessory: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.accessoryEnabled = accessoryEnabled
        self.usesNativeAccessory = usesNativeAccessory
        self.content = content()
        self.accessory = accessory()
    }

    @ViewBuilder
    public var body: some View {
#if os(iOS)
        if #available(iOS 26, *), usesNativeAccessory {
            content
        } else {
            contentWithAccessory
        }
#else
        content
#endif
    }

    @ViewBuilder
    private var contentWithAccessory: some View {
        if accessoryEnabled {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                accessory
                    .glassSurface(.waitingBar)
                    .padding(.horizontal, accessoryHorizontalPadding)
                    .padding(.vertical, 8)
            }
        } else {
            content
        }
    }

    private var accessoryHorizontalPadding: CGFloat {
#if os(iOS)
        if #available(iOS 26, *) { return 16 }
#endif
        return 12
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
                    .dynamicTypeSize(.large)
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

/// 実controllerの表示完了を読み取り、現在選択されたタブだけへ通知する。
public struct DSViewDidAppearObserver: View {
    private let role: String
    private let onAppear: () -> Void

    public init(role: String, onAppear: @escaping () -> Void) {
        self.role = role
        self.onAppear = onAppear
    }

    public var body: some View {
#if os(iOS)
        DSSelectedTabAppearanceController(role: role, onAppear: onAppear)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
#else
        Color.clear.onAppear(perform: onAppear)
#endif
    }
}

#if os(iOS)
private struct DSSelectedTabAppearanceController: UIViewControllerRepresentable {
    let role: String
    let onAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.role = role
        controller.onAppear = onAppear
        controller.trace("make")
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.role = role
        controller.onAppear = onAppear
        controller.trace("update")
    }

    final class Controller: UIViewController {
        var role = ""
        var onAppear: () -> Void = {}

        override func loadView() {
            let content = UIView()
            content.backgroundColor = .clear
            content.isUserInteractionEnabled = false
            view = content
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            trace("didAppear")
            guard view.window != nil, belongsToSelectedTab else { return }
            onAppear()
        }

        private var belongsToSelectedTab: Bool {
            guard let selected = tabBarController?.selectedViewController else { return false }
            var controller: UIViewController? = self
            while let current = controller {
                if current === selected { return true }
                controller = current.parent
            }
            return false
        }

        func trace(_ event: String) {
#if DEBUG
            print("[TabLifecycle] role=\(role) event=\(event) window=\(viewIfLoaded?.window != nil) selected=\(belongsToSelectedTab)")
#endif
        }
    }
}
#endif
