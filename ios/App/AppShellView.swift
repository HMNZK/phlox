import SwiftUI
import UIKit
import DesignSystemIOS
import Features
import PhloxCore

/// OS 標準のタブと、一覧・設定で共有する下端の対応待ち表示。
struct AppShellView<SessionsContent: View, SettingsContent: View>: View {
    @Binding private var selection: AppTab?
    let navigationState: SessionNavigationState
    let reachability: Reachability
    let lastFetchedAt: Date?
    let host: String?
    let hidesTabBar: Bool
    let hidesAccessory: Bool
    let onOpenSession: (String) -> Void
    let onShowSessionList: () -> Void
    let onReconnect: () -> Void
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
        onOpenSession: @escaping (String) -> Void,
        onShowSessionList: @escaping () -> Void,
        onReconnect: @escaping () -> Void,
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
        self.onOpenSession = onOpenSession
        self.onShowSessionList = onShowSessionList
        self.onReconnect = onReconnect
        sessionsContent = sessions()
        settingsContent = settings()
    }

    var body: some View {
        let accessoryEnabled = !hidesAccessory && navigationState.accessory != nil

        DSPlatformTabView(
            selection: $selection,
            accessoryEnabled: accessoryEnabled
        ) {
            Tab(value: AppTab.sessions as AppTab?) {
                DSPlatformTabContent(accessoryEnabled: accessoryEnabled) {
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

            Tab(value: AppTab.settings as AppTab?) {
                DSPlatformTabContent(accessoryEnabled: accessoryEnabled) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("開く")
                        Image(systemName: "chevron.right")
                            .font(DSFont.caption.weight(.semibold))
                    }
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(IOSColor.accentOnFill)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(IOSColor.accent, in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

        return Button(action: onReconnect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac に届きません")
                        .font(DSFont.subheadline.weight(.bold))
                        .foregroundStyle(IOSColor.status.error)
                        .lineLimit(1)
                    Text("\(lastUpdated) · スリープ中か Tailscale 切断")
                        .font(DSFont.footnote)
                        .foregroundStyle(IOSColor.text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("再接続を試す")
                    .font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(IOSColor.text.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(IOSColor.bg.raised, in: Capsule())
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mac に届きません。\(lastUpdated) · スリープ中か Tailscale 切断。再接続を試す")
    }

    private func statusColor(for state: SessionDisplayState) -> Color {
        IOSStatusVocabulary.presentation(for: state, locale: Locale(identifier: "ja_JP")).color
            ?? IOSColor.text.primary
    }
}
