import SwiftUI
import UIKit
import DesignSystemIOS
import Features
import PhloxCore

/// OS 標準のタブと、一覧・設定で共有する下端の対応待ち表示。
struct AppShellView<SessionsContent: View, SettingsContent: View>: View {
    private enum PlatformTabSelection: Hashable {
        case sessions
        case settings
        case newChat
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var reconnectIndicatorSize: CGFloat = 14
    @Binding private var selection: AppTab?
    let navigationState: SessionNavigationState
    let reachability: Reachability
    let lastFetchedAt: Date?
    let host: String?
    let hidesTabBar: Bool
    let hidesAccessory: Bool
    let isReconnecting: Bool
    let onOpenSession: (String) -> Void
    let onShowSessionList: () -> Void
    let onReconnect: () -> Void
    let onNewChatTabAppear: () -> Void
    private let sessionsContent: SessionsContent
    private let settingsContent: SettingsContent

    init(
        selection: Binding<AppTab?>,
        navigationState: SessionNavigationState,
        reachability: Reachability,
        lastFetchedAt: Date?,
        host: String?,
        hidesTabBar: Bool,
        hidesAccessory: Bool,
        isReconnecting: Bool = false,
        onOpenSession: @escaping (String) -> Void,
        onShowSessionList: @escaping () -> Void,
        onReconnect: @escaping () -> Void,
        onNewChatTabAppear: @escaping () -> Void = {},
        @ViewBuilder sessions: () -> SessionsContent,
        @ViewBuilder settings: () -> SettingsContent
    ) {
        _selection = selection
        self.navigationState = navigationState
        self.reachability = reachability
        self.lastFetchedAt = lastFetchedAt
        self.host = host
        self.hidesTabBar = hidesTabBar
        self.hidesAccessory = hidesAccessory
        self.isReconnecting = isReconnecting
        self.onOpenSession = onOpenSession
        self.onShowSessionList = onShowSessionList
        self.onReconnect = onReconnect
        self.onNewChatTabAppear = onNewChatTabAppear
        sessionsContent = sessions()
        settingsContent = settings()
    }

    var body: some View {
        let accessoryEnabled = !hidesAccessory && navigationState.accessory != nil
        let usesNativeAccessory = navigationState.accessory != .offline

        DSPlatformTabView(
            selection: platformSelection,
            actionValue: .newChat,
            accessoryEnabled: accessoryEnabled && usesNativeAccessory,
            onActionTabAppear: onNewChatTabAppear
        ) {
            Tab(value: PlatformTabSelection.sessions) {
                DSPlatformTabContent(accessoryEnabled: accessoryEnabled, usesNativeAccessory: usesNativeAccessory) {
                    sessionsContent
                } accessory: {
                    accessoryContent
                }
            } label: {
                Label {
                    Text("セッション")
                } icon: {
                    tabIcon("bubble.left.and.bubble.right")
                }
                .accessibilityLabel(navigationState.sessionsTabAccessibilityLabel)
            }
            .badge(navigationState.badgeCount == 0 ? nil : Text("\(navigationState.badgeCount)"))

            Tab(value: PlatformTabSelection.settings) {
                DSPlatformTabContent(accessoryEnabled: accessoryEnabled, usesNativeAccessory: usesNativeAccessory) {
                    settingsContent
                } accessory: {
                    accessoryContent
                }
            } label: {
                Label {
                    Text("設定")
                } icon: {
                    tabIcon("gearshape")
                }
            }
        } accessory: {
            accessoryContent
        }
        .toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
    }

    private var platformSelection: Binding<PlatformTabSelection> {
        Binding(
            get: {
                switch selection {
                case .sessions: .sessions
                case .settings: .settings
                case nil: .newChat
                }
            },
            set: { tab in
                switch tab {
                case .sessions: selection = .sessions
                case .settings: selection = .settings
                case .newChat: selection = nil
                }
            }
        )
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if !hidesAccessory {
            switch navigationState.accessory {
            case .attention:
                attentionAccessory
            case .offline:
                offlineAccessory
            case nil:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func tabIcon(_ name: String) -> Image {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        if let symbol = UIImage(systemName: name, withConfiguration: configuration) {
            return Image(uiImage: symbol)
        }
        return Image(systemName: name)
    }

    @ViewBuilder
    private var attentionAccessory: some View {
        if let first = navigationState.firstAttentionItem {
            Button {
                onOpenSession(first.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("対応待ち \(navigationState.badgeCount)")
                            .font(DSFont.subheadline.weight(.bold))
                            .foregroundStyle(IOSColor.text.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(first.name)
                            Text("·")
                            Text(first.statusLabel)
                                .foregroundStyle(statusColor(for: first.displayState))
                        }
                        .font(DSFont.footnote)
                        .foregroundStyle(IOSColor.text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("開く")
                        Image(systemName: "chevron.right")
                            .font(DSFont.caption.weight(.semibold))
                    }
                    .font(DSFont.subheadline.weight(.semibold))
                    .dynamicTypeSize(.large)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(IOSColor.accentOnFill)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(IOSColor.accent, in: Capsule())
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressFeedbackStyle())
            .accessibilityLabel(
                "対応待ち \(navigationState.badgeCount) 件。先頭は \(first.name)、\(first.statusLabel)。開く"
            )
            .contextMenu {
                ForEach(navigationState.attentionItems) { item in
                    Button {
                        onOpenSession(item.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("\(item.statusLabel) · \(item.agent.displayName) · \(item.projectLabel)")
                                .font(.footnote)
                        }
                    }
                }
                Divider()
                Button("セッション一覧で見る", systemImage: "list.bullet", action: onShowSessionList)
            }
        }
    }

    private var offlineAccessory: some View {
        let viewModel = UnreachableViewModel(
            reachability: reachability,
            host: host,
            lastUpdated: lastFetchedAt,
            onRetry: {}
        )
        let lastUpdated = viewModel.lastUpdatedText() ?? "最終取得なし"
        let subtitle = reachability == .unreachableHost
            ? "\(lastUpdated) · スリープ中か Tailscale 切断"
            : lastUpdated
        let reconnectTitle = isReconnecting ? "再接続しています…" : "再接続を試す"
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        return Button {
            guard !isReconnecting else { return }
            onReconnect()
        } label: {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.cardTitle)
                        .font(DSFont.subheadline.weight(.bold))
                        .foregroundStyle(reachability == .unreachableHost ? IOSColor.status.error : IOSColor.text.primary)
                    Text(subtitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(IOSColor.text.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if isReconnecting {
                        reconnectIndicator
                    }
                    Text(reconnectTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(DSFont.subheadline.weight(.semibold))
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                .foregroundStyle(IOSColor.text.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(IOSColor.bg.raised, in: Capsule())
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressFeedbackStyle())
        .disabled(isReconnecting)
        .accessibilityIdentifier("shell.offline.reconnect")
        .accessibilityLabel("\(viewModel.cardTitle)。\(subtitle)。\(reconnectTitle)")
    }

    private var reconnectIndicator: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(DSMotion.spinnerRotation(
                    at: context.date.timeIntervalSinceReferenceDate,
                    reduceMotion: reduceMotion
                )))
        }
        .frame(width: reconnectIndicatorSize, height: reconnectIndicatorSize)
        .accessibilityHidden(true)
    }

    private func statusColor(for state: SessionDisplayState) -> Color {
        IOSStatusVocabulary.presentation(for: state, locale: Locale(identifier: "ja_JP")).color
            ?? IOSColor.text.primary
    }
}
