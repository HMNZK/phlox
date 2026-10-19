// ImageRenderer は NavigationStack を含む画面を正しく描けないため、UIWindow の drawHierarchy を使う。
// 公開操作とアクセシビリティ操作で状態を作り、画面サイズ・安全領域・配色・文字サイズを指定する。
import SwiftUI
import UIKit
import Testing
import AgentDomain
import ImageAttachmentKit
@testable import Features
import PhloxCore
import PhloxNetworking
import DesignSystemIOS
@testable import PhloxMobile

@MainActor
struct DesignSnapshotRenderTests {
    @Test func renderDesignSnapshots() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard variables["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }
        try #require(UITestingSupport.isEnabled, "Snapshot host must launch with -UITesting to use the stub environment")
        FileHandle.standardError.write(Data("[snapshot host] -UITesting enabled; stub composition selected\n".utf8))
        let output = try outputDirectory(variables: variables)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let iOSMajor = UIDevice.current.systemVersion.split(separator: ".").first ?? "unknown"
        let osSuffix = "-ios\(iOSMajor)"
        let selectedInputScenes = variables["PHLOX_SNAPSHOT_INPUT_SCENES"].map {
            Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        let selectedDetailScenes = variables["PHLOX_SNAPSHOT_DETAIL_SCENES"].map {
            Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        let selectedScreenScenes = variables["PHLOX_SNAPSHOT_SCREEN_SCENES"].map {
            Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        try #require([selectedInputScenes, selectedDetailScenes, selectedScreenScenes].compactMap { $0 }.count <= 1, "Select only one scene filter")
        if let selectedInputScenes {
            try #require(!selectedInputScenes.isEmpty, "PHLOX_SNAPSHOT_INPUT_SCENES must name input scenes")
            print("partial input snapshots only: \(selectedInputScenes.sorted().joined(separator: ",")); not the full render gate")
        }

        let animations = UIView.areAnimationsEnabled
        let preferences = UserDefaults.standard
        let previousTheme = preferences.object(forKey: ThemeStore.themeKey)
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animations)
            if let previousTheme {
                preferences.set(previousTheme, forKey: ThemeStore.themeKey)
            } else {
                preferences.removeObject(forKey: ThemeStore.themeKey)
            }
            DSNavigationChrome.installUIKitAppearanceIfNeeded()
        }

        if let selectedScreenScenes {
            let known: Set<String> = ["SetSE", "SetSEDark", "ShellSE", "ListSE", "DraftMoreSE", "DraftMoreDT", "DraftSpawning", "DraftSending", "DraftCreating", "DraftFailedAX5", "DraftFailedAX5SE", "PairGateFailAX5", "PairGateFailAX5SE2"]
            try #require(!selectedScreenScenes.isEmpty && selectedScreenScenes.isSubset(of: known), "Unknown or empty screen scenes: \(selectedScreenScenes.sorted())")
            print("partial screen snapshots only: \(selectedScreenScenes.sorted().joined(separator: ",")); not the full render gate")
            try await renderNarrowScreenSnapshots(output: output, osSuffix: osSuffix, selectedScenes: selectedScreenScenes)
            try await renderNewChatSnapshots(output: output, variables: variables, osSuffix: osSuffix, selectedScenes: selectedScreenScenes)
            try await renderPairSettingsSnapshots(output: output, osSuffix: osSuffix, selectedScenes: selectedScreenScenes)
            return
        }
        if let selectedDetailScenes {
            try #require(!selectedDetailScenes.isEmpty, "PHLOX_SNAPSHOT_DETAIL_SCENES must name detail scenes")
            print("partial detail snapshots only: \(selectedDetailScenes.sorted().joined(separator: ",")); not the full render gate")
            try await renderSessionDetailSnapshots(output: output, osSuffix: osSuffix, selectedScenes: selectedDetailScenes)
            return
        }
        if selectedInputScenes == nil {
        try await renderGlanceSnapshots(output: output, osSuffix: osSuffix)
        try await renderPairSettingsSnapshots(output: output, osSuffix: osSuffix)

        for screen in [UITestingSupport.Screen.sessionList] {
            let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: screen)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            try #require(!list.allSessions.isEmpty)
            defer { list.stop() }
            for (width, height, dark, ax5) in [
                (428, 926, false, false), (428, 926, true, false),
                (375, 667, false, false), (375, 667, true, false),
                (428, 926, false, true),
            ] {
                let themeID = AppearancePreference.system.themeID(systemColorScheme: dark ? .dark : .light)
                preferences.set(themeID, forKey: ThemeStore.themeKey)
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
                let size = CGSize(width: width, height: height)
                let content = NavigationStack {
                    SessionListView(
                        viewModel: list, reachability: .online,
                        onSelectDetail: { _ in }, onAddSession: { _ in }
                    )
                }
                .dsCampNavigationChrome()
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.dynamicTypeSize, ax5 ? .accessibility5 : .large)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .frame(width: size.width)

                let safeArea = width == 428
                    ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                let scale: CGFloat = 2
                let image = try await windowImage(
                    content,
                    size: size,
                    safeArea: safeArea,
                    scale: scale,
                    dark: dark, scenarioID: screen.rawValue
                )
                try writeSnapshot(
                    image,
                    name: "\(screen.rawValue)-\(width)x\(height)-\(dark ? "dark" : "light")\(ax5 ? "-ax5" : "")\(osSuffix).png",
                    to: output,
                    expectedSize: size,
                    expectedScale: scale
                )
            }
        }

        try await renderSessionDetailSnapshots(output: output, osSuffix: osSuffix)

        var shellScreens: [UITestingSupport.Screen] = [
            .sessionShell, .sessionShellNoAttention, .sessionShellOffline, .sessionShellDetail,
        ]
        if iOSMajor == "26" {
            shellScreens.append(.sessionShellScrolled)
        }
        for screen in shellScreens {
            let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: screen)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            defer { list.stop() }
            try #require(!list.lastKnownSessions.isEmpty)

            let offline = screen == .sessionShellOffline
            let reachability: Reachability = offline ? .unreachableHost : .online
            let navigationState = SessionNavigationState.resolve(
                listState: list.state,
                lastKnownSessions: list.lastKnownSessions,
                reachability: reachability
            )
            var detailModel: SessionDetailViewModel?
            if screen == .sessionShellDetail {
                let session = try #require(list.session(id: "list-approval"))
                let detail = SessionDetailViewModel(session: session, api: environment.apiClient)
                await detail.load()
                try #require(detail.showsChat)
                detailModel = detail
            }

            let settings = AppSettings(store: InMemoryAppSettingsStore(faceIDEnabled: !offline, appearance: .system))
            let connection = ConnectionSettingsViewModel(
                tokenStore: environment.tokenStore,
                configStore: InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765)),
                probe: { _, _ in true }
            )
            let selectedTab: AppTab? = offline ? .settings : .sessions
            let sessionList = SessionListView(
                viewModel: list,
                reachability: reachability,
                endpoint: "100.64.0.1:8765",
                onSelectDetail: { _ in },
                onAddSession: { _ in },
                initialExpandedSessionIDs: ["refactor"]
            )
            let content = AppShellView(
                selection: .constant(selectedTab),
                navigationState: navigationState,
                reachability: reachability,
                lastFetchedAt: offline ? Date().addingTimeInterval(-180) : list.lastFetchedAt,
                host: "100.64.0.1",
                hidesTabBar: screen == .sessionShellDetail,
                hidesAccessory: screen == .sessionShellDetail,
                onOpenSession: { _ in },
                onShowSessionList: {},
                onReconnect: {}
            ) {
                NavigationStack {
                    if let detailModel {
                        SessionDetailView(viewModel: detailModel, onDelete: {})
                    } else {
                        sessionList.defaultScrollAnchor(screen == .sessionShellScrolled ? .bottom : .top)
                    }
                }
                .dsCampNavigationChrome()
            } settings: {
                NavigationStack {
                    SettingsView(
                        viewModel: SettingsViewModel(settings: settings),
                        connectionViewModel: connection,
                        onQRScan: {},
                        reachability: reachability,
                        lastFetchedAt: offline ? Date().addingTimeInterval(-180) : list.lastFetchedAt
                    )
                }
                .dsCampNavigationChrome()
            }
            let size = CGSize(width: 428, height: 926)
            print("rendering shell snapshot: \(screen.rawValue)")
            let image = try await windowImage(
                content
                    .environment(\.colorScheme, .light)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .frame(width: size.width),
                size: size,
                safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                scale: 2,
                dark: false, scenarioID: screen.snapshotName
            )
            try writeSnapshot(
                image,
                name: "\(screen.snapshotName)-428x926-light\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: 2
            )

            if screen == .sessionShell {
                var variants: [(name: String, width: CGFloat, height: CGFloat, dark: Bool, ax5: Bool)] = [
                    ("ShellDark", 428, 926, true, false),
                    ("ShellDT", 428, 926, false, true),
                    ("ShellSE", 375, 667, false, false),
                ]
                if iOSMajor == "18" {
                    variants.append(("Shell18", 428, 926, false, false))
                }
                for variant in variants {
                    let variantTheme = AppearancePreference.system.themeID(
                        systemColorScheme: variant.dark ? .dark : .light
                    )
                    preferences.set(variantTheme, forKey: ThemeStore.themeKey)
                    DSNavigationChrome.installUIKitAppearanceIfNeeded(for: variantTheme)
                    let variantSize = CGSize(width: variant.width, height: variant.height)
                    let variantSafeArea = variant.width == 428
                        ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                        : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                    let variantImage = try await windowImage(
                        content
                            .environment(\.colorScheme, variant.dark ? .dark : .light)
                            .environment(\.dynamicTypeSize, variant.ax5 ? .accessibility5 : .large)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .frame(width: variantSize.width),
                        size: variantSize,
                        safeArea: variantSafeArea,
                        scale: 2,
                        dark: variant.dark, scenarioID: variant.name
                    )
                    try writeSnapshot(
                        variantImage,
                        name: "\(variant.name)-\(Int(variant.width))x\(Int(variant.height))-\(variant.dark ? "dark" : "light")\(variant.ax5 ? "-ax5" : "")\(osSuffix).png",
                        to: output,
                        expectedSize: variantSize,
                        expectedScale: 2
                    )
                }
            }
        }

        let listScreens: [UITestingSupport.Screen] = [
            .list, .listMulti, .listCollapsed, .listChildrenExpanded, .listAllAttention,
            .listLoading, .listJudging, .listEmpty, .listOffNet, .listOffHost, .listOffUnknown,
            .listError, .listError401, .listSE, .listDT,
        ]
        for screen in listScreens {
            print("rendering list snapshot: \(screen.rawValue)")
            let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: screen)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            defer { list.stop() }
            if screen == .listOffNet || screen == .listOffHost || screen == .listOffUnknown {
                list.seedStateForUITesting(.offline)
            }

            let reachability: Reachability = switch screen {
            case .listJudging, .listOffUnknown: .unknown
            case .listOffNet: .offlineNetwork
            case .listOffHost: .unreachableHost
            default: .online
            }
            let navigationState = SessionNavigationState.resolve(
                listState: list.state,
                lastKnownSessions: list.lastKnownSessions,
                reachability: reachability
            )
            let settings = AppSettings(store: InMemoryAppSettingsStore(appearance: .system))
            let connection = ConnectionSettingsViewModel(
                tokenStore: environment.tokenStore,
                configStore: InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765)),
                probe: { _, _ in true }
            )

            let layouts: [(width: CGFloat, height: CGFloat, dark: Bool, ax5: Bool)] = switch screen {
            case .list:
                [(428, 926, false, false), (428, 926, true, false)]
            case .listSE:
                [(375, 667, false, false), (375, 667, true, false)]
            case .listDT:
                [(428, 926, false, true)]
            case .listMulti, .listLoading, .listEmpty, .listOffHost:
                [(428, 926, false, false), (428, 926, true, false)]
            default:
                [(428, 926, false, false)]
            }

            for layout in layouts {
                let themeID = AppearancePreference.system.themeID(systemColorScheme: layout.dark ? .dark : .light)
                preferences.set(themeID, forKey: ThemeStore.themeKey)
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
                let size = CGSize(width: layout.width, height: layout.height)
                let expandedGroups: Set<String>? = screen == .listCollapsed ? ["id:simple-budget"] : nil
                let expandedSessions: Set<String> = switch screen {
                case .listChildrenExpanded: ["refactor", "csv-import"]
                case .listCollapsed: []
                default: ["refactor"]
                }
                let sessionList = SessionListView(
                    viewModel: list,
                    reachability: reachability,
                    endpoint: "100.64.0.1:8765",
                    onSelectDetail: { _ in },
                    onAddSession: { _ in },
                    initialExpandedGroupIDs: expandedGroups,
                    initialExpandedSessionIDs: expandedSessions
                )
                let content = AppShellView(
                    selection: .constant(AppTab.sessions),
                    navigationState: navigationState,
                    reachability: reachability,
                    lastFetchedAt: list.lastFetchedAt,
                    host: "100.64.0.1",
                    hidesTabBar: false,
                    hidesAccessory: false,
                    onOpenSession: { _ in },
                    onShowSessionList: {},
                    onReconnect: {}
                ) {
                    NavigationStack {
                        sessionList
                    }
                        .dsCampNavigationChrome()
                } settings: {
                    NavigationStack {
                        SettingsView(
                            viewModel: SettingsViewModel(settings: settings),
                            connectionViewModel: connection,
                            onQRScan: {},
                            reachability: reachability,
                            lastFetchedAt: list.lastFetchedAt
                        )
                    }
                    .dsCampNavigationChrome()
                }
                .environment(\.colorScheme, layout.dark ? .dark : .light)
                .environment(\.dynamicTypeSize, layout.ax5 ? .accessibility5 : .large)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .frame(width: size.width)

                let safeArea = layout.width == 428
                    ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                let scale: CGFloat = 2
                let image = try await windowImage(
                    content,
                    size: size,
                    safeArea: safeArea,
                    scale: scale,
                    dark: layout.dark, scenarioID: screen.snapshotName
                )
                try writeSnapshot(
                    image,
                    name: "\(screen.snapshotName)-\(Int(layout.width))x\(Int(layout.height))-\(layout.dark ? "dark" : "light")\(layout.ax5 ? "-ax5" : "")\(osSuffix).png",
                    to: output,
                    expectedSize: size,
                    expectedScale: scale
                )
                let darkBoardName: String? = switch screen {
                case .list: "ListDark"
                case .listMulti: "ListMultiDark"
                case .listLoading: "ListLoadingDark"
                case .listEmpty: "ListEmptyDark"
                case .listOffHost: "ListOffHostDark"
                case .listSE: "ListSEDark"
                default: nil
                }
                if layout.dark, let darkBoardName {
                    try writeSnapshot(
                        image,
                        name: "\(darkBoardName)-\(Int(layout.width))x\(Int(layout.height))-dark\(osSuffix).png",
                        to: output,
                        expectedSize: size,
                        expectedScale: scale
                    )
                }
            }
        }

        let manyEnvironment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: .listManyTop)
        let manyList = SessionListViewModel(
            repository: manyEnvironment.sessionRepository,
            api: manyEnvironment.apiClient
        )
        await manyList.observe()
        try #require(manyList.allSessions.count == 25)
        #expect(manyList.allSessions.filter(\.needsAttention).count == 3)
        for (name, anchor) in [("ListManyTop", UnitPoint.top), ("ListManyScrolled", UnitPoint.bottom)] {
            let manySessionList = SessionListView(
                viewModel: manyList,
                reachability: .online,
                endpoint: "100.64.0.1:8765",
                onSelectDetail: { _ in },
                onAddSession: { _ in },
                initialExpandedSessionIDs: ["many-refactor"]
            )
            let content = AppShellView(
                selection: .constant(AppTab.sessions),
                navigationState: SessionNavigationState.resolve(
                    listState: manyList.state,
                    lastKnownSessions: manyList.lastKnownSessions,
                    reachability: .online
                ),
                reachability: .online,
                lastFetchedAt: manyList.lastFetchedAt,
                host: "100.64.0.1",
                hidesTabBar: false,
                hidesAccessory: false,
                onOpenSession: { _ in }, onShowSessionList: {}, onReconnect: {}
            ) {
                NavigationStack { manySessionList.defaultScrollAnchor(anchor) }
                    .dsCampNavigationChrome()
            } settings: {
                NavigationStack { EmptyView() }
                    .dsCampNavigationChrome()
            }
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: 428)
            let size = CGSize(width: 428, height: 926)
            let image = try await windowImage(
                content,
                size: size,
                safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                scale: 2,
                dark: false, scenarioID: name,
                prepareWindow: { window in
                    try await waitForExpandedListGeometry(window, scenarioID: name, output: output)
                }
            )
            try writeSnapshot(
                image,
                name: "\(name)-428x926-light\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: 2
            )
        }
        manyList.stop()

        for dark in [false, true] {
            let themeID = AppearancePreference.system.themeID(systemColorScheme: dark ? .dark : .light)
            preferences.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let size = CGSize(width: 428, height: 926)
            let content = ComponentSnapshotView()
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.dynamicTypeSize, .large)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .frame(width: size.width, height: size.height)
            let image = try await windowImage(
                content,
                size: size,
                safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                scale: 2,
                dark: dark, scenarioID: "components"
            )
            try writeSnapshot(
                image,
                name: "components-428x926-\(dark ? "dark" : "light")\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: 2
            )
        }

        }

        let inputScenarios: [InputBarSnapshotScenario] = [
            .init(name: "ReplySending", isSending: true),
            .init(name: "ReplyPermDanger", permission: "bypassPermissions"),
            .init(name: "ReplyPermFail", permission: "manual", settingsError: "権限を変更できませんでした。今の権限（Manual）のままです。もう一度選んでください"),
            .init(name: "ReplyMore", width: 375, height: 667),
            .init(name: "ReplyInputDT", isAccessibilitySize: true),
            .init(name: "ReplyAttach", text: "この2枚の502の画面を見て原因を探して [Image #1] [Image #2]", attachmentCount: 2),
            .init(name: "ReplyAttachDark", dark: true, text: "この2枚の502の画面を見て原因を探して [Image #1] [Image #2]", attachmentCount: 2),
            .init(
                name: "ReplyAttachErr",
                text: "ログの画面 [Image #1] [Image #2] [Image #3] [Image #4]",
                attachmentCount: 4,
                attachmentError: "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。"
            ),
            .init(name: "ReplyAttachErrDim", text: "ログの画面 [Image #1]", attachmentCount: 1,
                  attachmentError: "画像は各辺8000ピクセルまでです。必要な部分を切り出してください"),
            .init(name: "ReplyAttachErrDimDark", dark: true, text: "ログの画面 [Image #1]", attachmentCount: 1,
                  attachmentError: "画像は各辺8000ピクセルまでです。必要な部分を切り出してください"),
            .init(name: "ReplyAttachErrDimSE", width: 375, height: 667, text: "ログの画面 [Image #1]", attachmentCount: 1,
                  attachmentError: "画像は各辺8000ピクセルまでです。必要な部分を切り出してください"),
            .init(name: "ReplyAttachErrLoad", text: "ログの画面 [Image #1] [Image #2]", attachmentCount: 2,
                  attachmentError: "画像を読み込めませんでした"),
            .init(name: "ReplyAttachErrSize", text: "ログの画面 [Image #1] [Image #2]", attachmentCount: 2,
                  attachmentError: "画像は1枚あたり20MBまでです"),
            .init(name: "ReplyAttachErrTotal", text: "ログの画面 [Image #1] [Image #2] [Image #3]", attachmentCount: 3,
                  attachmentError: "画像は合計80MBまでです"),
            .init(name: "UsageNormal"),
            .init(name: "UsageLow", usageStyle: .low),
            .init(name: "UsageNa", usageStyle: .unavailable),
            .init(name: "UsageStale", usageState: .failed),
            .init(name: "UsageRefresh", usageState: .loading),
            .init(name: "UsageNormalDT", isAccessibilitySize: true),
            .init(name: "UsageNormalDark", dark: true),
            .init(name: "UsageNormalSE", width: 375, height: 667, showsSessionDetailChrome: true),
            .init(name: "UsageLowDT", isAccessibilitySize: true, usageStyle: .low, showsSessionDetailChrome: true),
            .init(name: "UsageLowDark", dark: true, usageStyle: .low, showsSessionDetailChrome: true),
            .init(name: "UsageLowSE", width: 375, height: 667, usageStyle: .low, showsSessionDetailChrome: true),
            .init(name: "UsageNaDT", isAccessibilitySize: true, usageStyle: .unavailable, showsSessionDetailChrome: true),
            .init(name: "UsageNaDark", dark: true, usageStyle: .unavailable, showsSessionDetailChrome: true),
            .init(name: "UsageNaSE", width: 375, height: 667, usageStyle: .unavailable, showsSessionDetailChrome: true),
            .init(name: "UsagePop", showsUsagePopover: true),
            .init(name: "UsagePopDT", isAccessibilitySize: true, showsUsagePopover: true, showsSessionDetailChrome: true),
            .init(name: "UsagePopSE", width: 375, height: 667, showsUsagePopover: true, showsSessionDetailChrome: true),
            .init(name: "UsagePopDark", dark: true, showsUsagePopover: true),
            .init(name: "UsageStaleDT", isAccessibilitySize: true, usageState: .failed, showsSessionDetailChrome: true),
            .init(name: "UsageStaleDTSE", width: 375, height: 667, isAccessibilitySize: true, usageState: .failed, showsSessionDetailChrome: true),
            .init(name: "UsageStaleDark", dark: true, usageState: .failed, showsSessionDetailChrome: true),
            .init(name: "UsageStaleSE", width: 375, height: 667, usageState: .failed, showsSessionDetailChrome: true),
        ]

        if let selectedInputScenes {
            let unknown = selectedInputScenes.subtracting(Set(inputScenarios.map(\.name)))
            try #require(unknown.isEmpty, "Unknown input scenes: \(unknown.sorted())")
        }
        let attachmentPreviews = [
            snapshotAttachmentData(color: UIColor(red: 0.82, green: 0.82, blue: 0.87, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.55, green: 0.75, blue: 0.63, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.88, green: 0.73, blue: 0.62, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.56, green: 0.67, blue: 0.82, alpha: 1)),
        ]
        let inputEnvironment = AppEnvironment.uiTesting(scenario: .empty)
        let inputList = SessionListViewModel(repository: inputEnvironment.sessionRepository, api: inputEnvironment.apiClient)
        await inputList.observe()
        defer { inputList.stop() }
        for scenario in inputScenarios {
            guard selectedInputScenes?.contains(scenario.name) ?? true else { continue }
            let themeID = AppearancePreference.system.themeID(systemColorScheme: scenario.dark ? .dark : .light)
            preferences.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let size = CGSize(width: scenario.width, height: scenario.height)
            let safeArea = scenario.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let session = Session(
                id: "input-\(scenario.name)", name: "refactor: ControlServer proxy",
                agent: .claudeCode, status: .idle, projectName: "Phlox", updatedAt: UITestUsageFixtures.asOfDate
            )
            let usageBoard = scenario.name.hasPrefix("Usage")
            let messages: [ChatMessage] = [
                .command(id: "input-command", command: usageBoard ? "swiftlint lint --strict" : "swift test --package-path macos/Packages/ControlServer", output: "Exit code 0\nok"),
                .agent(id: "input-agent", text: usageBoard ? "lint の指摘 3 件を直しました。テストと lint はすべて通っています。" : "テストは 50 件すべて成功しました。次は何をしますか？"),
                .turnCost(id: "input-cost", costUSD: 0.42),
            ]
            let gate = SnapshotResponseGate()
            let usageSource = SnapshotUsageSource(style: scenario.usageStyle)
            let readiness = SessionDetailSnapshotReadiness()
            let api = SessionDetailSnapshotAPI(
                session: session, messages: .success(messages), approvals: [],
                turnUsage: TurnUsage(costUSD: 0.42, contextUsedTokens: 44_000, contextWindowTokens: 200_000),
                readiness: readiness, permission: scenario.permission, usageStyle: scenario.usageStyle,
                sendGate: scenario.isSending ? gate : nil,
                failsSettings: scenario.settingsError != nil, usageSource: usageSource
            )
            let recovery: SessionDetailRecovery?
            if scenario.name == "ReplyAttachErrTotal" {
                var restoredData = attachmentPreviews[0]
                restoredData.append(Data(count: 70_000_000 - restoredData.count))
                let restoredItems = (0..<scenario.attachmentCount).map { index in
                    SessionDetailViewModel.SessionAttachmentItem(
                        number: index + 1,
                        send: SendAttachment(mediaType: "image/png", data: index == 0 ? restoredData : attachmentPreviews[index]),
                        previewData: attachmentPreviews[index]
                    )
                }
                recovery = SessionDetailRecovery(
                    text: scenario.text, attachments: restoredItems,
                    errorMessage: ImageAttachmentLimits.inputTotalMessage
                )
            } else {
                recovery = nil
            }
            let model = SessionDetailViewModel(session: session, api: api, recovery: recovery)
            await model.load()
            await model.loadModelSettings()
            if recovery == nil {
                model.addAttachments((0..<scenario.attachmentCount).map {
                    SendAttachment(mediaType: "image/png", data: attachmentPreviews[$0 % attachmentPreviews.count])
                })
            }
            model.inputText = scenario.isSending
                ? "この2枚の502の画面を見て原因を探して"
                : scenario.text
            model.inputCursorUTF16 = model.inputText.utf16.count
            switch scenario.name {
            case "ReplyAttachErr":
                model.addAttachments([SendAttachment(mediaType: "image/png", data: attachmentPreviews[0])])
            case "ReplyAttachErrLoad":
                await model.addAttachmentLoadResults([.failure(ImageAttachmentPreparationError.invalidImage)])
            case "ReplyAttachErrDim", "ReplyAttachErrDimDark", "ReplyAttachErrDimSE":
                model.addAttachments([SendAttachment(mediaType: "image/png", data: snapshotDimensionOverflowData())])
            case "ReplyAttachErrSize":
                model.addAttachments([SendAttachment(mediaType: "image/png", data: Data(count: ImageAttachmentLimits.maxInputBytes + 1))])
            case "ReplyAttachErrTotal":
                #expect(model.attachmentError == nil)
                let restoredItems = model.attachmentItems
                var additionalData = attachmentPreviews[0]
                additionalData.append(Data(count: ImageAttachmentLimits.maxInputBytes - additionalData.count))
                model.addAttachments([SendAttachment(mediaType: "image/png", data: additionalData)])
                #expect(model.attachmentItems == restoredItems)
            case "ReplyPermFail": await model.selectPermission("bypassPermissions")
            default: break
            }
            if let expected = scenario.attachmentError { #expect(model.attachmentError == expected) }
            if scenario.settingsError != nil { #expect(model.settingsChangeError != nil) }

            let usageViewModel = UsageViewModel(
                api: api, agents: [], state: .idle, lastSuccessfulAt: nil,
                now: { UITestUsageFixtures.asOfDate }
            )
            await usageViewModel.load()
            await usageSource.configure(
                fails: scenario.usageState == .failed,
                gate: scenario.usageState == .loading ? gate : nil
            )
            if scenario.usageState == .failed {
                await usageViewModel.load()
                #expect(!usageViewModel.shouldShowRow)
                #expect(!usageViewModel.isStale)
            }
            var pending: Task<Void, Never>?
            if scenario.isSending {
                model.addAttachments(attachmentPreviews.prefix(2).map { SendAttachment(mediaType: "image/png", data: $0) })
                pending = Task { await model.sendMessage() }
            } else if scenario.usageState == .loading {
                pending = Task { await usageViewModel.load() }
            }
            let snapshot = SessionDetailSnapshotCase(name: scenario.name, session: session, messages: .success(messages))
            let content = SessionDetailSnapshotHost(
                list: inputList,
                navigationState: SessionNavigationState.resolve(listState: inputList.state, lastKnownSessions: inputList.lastKnownSessions, reachability: .online),
                snapshot: snapshot, session: session, api: api, preparedModel: model
            )
            .environment(\.usageViewModel, usageViewModel)
            .environment(\.colorScheme, scenario.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, scenario.isAccessibilitySize ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            let scale: CGFloat = 2
            do {
                if pending != nil { try await gate.waitUntilEntered() }
                if scenario.isSending { try #require(model.isSending) }
                if scenario.usageState == .loading { try #require(usageViewModel.isRefreshing) }
                let image = try await windowImage(
                    content,
                    size: size,
                    safeArea: safeArea,
                    scale: scale,
                    dark: scenario.dark,
                    scenarioID: scenario.name,
                    contentSizeCategory: scenario.isAccessibilitySize ? .accessibilityExtraExtraExtraLarge : .large,
                    settleDelay: .milliseconds(800),
                    waitUntilReady: {
                        await readiness.waitForMessages()
                    },
                    prepareWindow: { window in
                        if scenario.usageState == .failed {
                            try #require(!usageViewModel.shouldShowRow)
                            try #require(snapshotAccessibilityElement(in: window, identifier: "UsageRingRow.button") == nil,
                                         "Failed usage must not leave a visible or accessible row")
                        }
                        if ["UsageStaleDT", "UsageStaleDTSE"].contains(scenario.name) {
                            try await verifyAX5FailureComposer(window, presentation: nil, draft: model.inputText,
                                scene: scenario.name, output: output, osSuffix: osSuffix, usageViewModel: usageViewModel)
                        }
                        if scenario.showsUsagePopover {
                            try #require(usageViewModel.shouldShowRow, "Usage fixtures must provide the real usage row")
                            if variables["PHLOX_SNAPSHOT_EXTERNAL_USAGE_ACTIVATION"] == "1" {
                                try await waitForExternalUsageActivation(window: window, output: output, sceneName: scenario.name)
                            } else {
                                let button = try await waitForSnapshotAccessibilityElement(in: window, identifier: "UsageRingRow.button")
                                try #require(button.accessibilityActivate(), "Usage row did not activate")
                            }
                            let deadline = ContinuousClock.now + .seconds(3)
                            while !snapshotHasPresentedPopover(window.rootViewController), ContinuousClock.now < deadline {
                                try await Task.sleep(for: .milliseconds(50))
                            }
                            try #require(snapshotHasPresentedPopover(window.rootViewController), "The real usage popover was not presented")
                            let popover = try #require(snapshotPresentedPopover(window.rootViewController))
                            try #require(popover.traitCollection.preferredContentSizeCategory == window.traitCollection.preferredContentSizeCategory)
                            try await Task.sleep(for: .milliseconds(150))
                            let externalLabels: Set<String>?
                            if variables["PHLOX_SNAPSHOT_EXTERNAL_USAGE_ACTIVATION"] == "1" {
                                externalLabels = try await waitForExternalPopoverAXEvidence(window: window, output: output, sceneName: scenario.name)
                            } else {
                                externalLabels = nil
                                for kind in [AgentKind.claudeCode, .codex, .cursor] {
                                    try #require(snapshotExposedAccessibilityElement(in: popover.view, label: kind.displayName) != nil,
                                                 "Usage popover content must be accessible before checking its layout")
                                }
                            }
                            if scenario.isAccessibilitySize {
                                try #require(popover.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
                            }
                            if let externalLabels {
                                try SnapshotExternalAXEvidence.validateUsageLayout(labels: externalLabels, isAccessibilitySize: scenario.isAccessibilitySize)
                            } else {
                                for header in UsageRingPresentation.popoverColumnHeaders {
                                    let headerExists = snapshotExposedAccessibilityElement(in: popover.view, label: header) != nil
                                    try #require(headerExists == !scenario.isAccessibilitySize,
                                                 "Usage popover column headers must match the actual text size")
                                }
                            }
                        }
                    }
                )
                try writeSnapshot(
                    image,
                    name: "\(scenario.name)-\(Int(scenario.width))x\(Int(scenario.height))-\(scenario.dark ? "dark" : "light")\(scenario.isAccessibilitySize ? "-ax5" : "")\(osSuffix).png",
                    to: output,
                    expectedSize: size,
                    expectedScale: scale
                )
            } catch {
                await gate.release()
                pending?.cancel()
                await pending?.value
                throw error
            }
            await gate.release()
            pending?.cancel()
            await pending?.value
        }

        if selectedInputScenes == nil {
            try await renderNewChatSnapshots(output: output, variables: variables, osSuffix: osSuffix)
        }
    }

    @Test func dotGothic16FontAndLicenseAreInHostedApp() throws {
        #expect(UIFont(name: "DotGothic16-Regular", size: 28) != nil)
        let licenseURL = try #require(Bundle.main.url(forResource: "OFL", withExtension: "txt"))
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(!license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func usageFixturesKeepMissingAndLowWindowsIndependent() throws {
        let low = UITestUsageFixtures.values(for: .low)
        let claude = try #require(low.first { $0.kind == .claudeCode })
        let cursor = try #require(low.first { $0.kind == .cursor })
        #expect(claude.buckets.map(\.usedPercent) == [88, 60])
        #expect(cursor.buckets.map(\.usedPercent) == [20, 91])
        let unavailable = UITestUsageFixtures.values(for: .unavailable)
        let codex = try #require(unavailable.first { $0.kind == .codex })
        #expect(codex.state == .ok)
        #expect(codex.buckets.map(\.id) == ["5h"])
        #expect(unavailable.first { $0.kind == .claudeCode }?.buckets.count == 2)
        #expect(unavailable.first { $0.kind == .cursor }?.state == .unavailable)
        let visible = UsageRingPresentation.agents(from: unavailable)
        #expect(visible.map(\.kind) == [.claudeCode, .codex])
        #expect(visible[1].buckets.map(\.id) == ["5h"])
    }

    @Test func specialFixturesUsePublicTransitionsAndFinishPendingRequests() async throws {
        let session = Session(id: "fixture-transitions", name: "fixture", agent: .claudeCode, status: .idle, updatedAt: .distantPast)
        let gate = SnapshotResponseGate()
        let usageSource = SnapshotUsageSource(style: .normal)
        let api = SessionDetailSnapshotAPI(
            session: session, messages: .success([]), approvals: [], turnUsage: nil,
            readiness: nil, permission: "manual", sendGate: gate, failsSettings: true, usageSource: usageSource
        )
        let model = SessionDetailViewModel(session: session, api: api)
        await model.loadModelSettings()
        await model.selectPermission("bypassPermissions")
        #expect(model.settingsChangeError != nil)
        await model.addAttachmentLoadResults([.failure(ImageAttachmentPreparationError.invalidImage)])
        #expect(model.attachmentError == "画像を読み込めませんでした")
        model.addAttachments([SendAttachment(mediaType: "image/png", data: snapshotDimensionOverflowData())])
        #expect(model.attachmentError == ImageAttachmentPreparationError.tooManyPixels.errorDescription)
        #expect(model.attachmentItems.isEmpty)
        model.addAttachments([SendAttachment(mediaType: "image/png", data: Data(count: ImageAttachmentLimits.maxInputBytes + 1))])
        #expect(model.attachmentError == ImageAttachmentLimits.inputSizeMessage)
        let image = snapshotAttachmentData(color: .systemGray)
        model.addAttachments(Array(repeating: SendAttachment(mediaType: "image/png", data: image), count: ImageAttachmentLimits.maxCount))
        model.addAttachments([SendAttachment(mediaType: "image/png", data: image)])
        #expect(model.attachmentError == ImageAttachmentLimits.countMessage)
        #expect(model.attachmentItems.count == ImageAttachmentLimits.maxCount)
        // 有効な画像だけの送信を保留し、キャンセル後の終了まで待つ。
        model.inputText = "fixture send"
        let pending = Task { await model.sendMessage() }
        do {
            try await gate.waitUntilEntered()
            #expect(model.isSending)
        } catch {
            pending.cancel()
            await pending.value
            throw error
        }
        pending.cancel()
        await pending.value
        #expect(!model.isSending)

        let usage = UsageViewModel(api: api)
        await usage.load()
        #expect(usage.state == .loaded)
        await usageSource.configure(fails: true, gate: nil)
        await usage.load()
        #expect(!usage.shouldShowRow)
        #expect(!usage.isStale)
        let refreshGate = SnapshotResponseGate()
        await usageSource.configure(fails: false, gate: refreshGate)
        let refresh = Task { await usage.load() }
        do {
            try await refreshGate.waitUntilEntered()
            #expect(usage.isRefreshing)
        } catch {
            refresh.cancel()
            await refresh.value
            throw error
        }
        await refreshGate.release()
        await refresh.value
        #expect(usage.state == .loaded)
        #expect(usage.shouldShowRow)
    }

    @Test func usagePopoverAccessibilitySearchRequiresExposedElements() {
        let root = UIView()
        #expect(snapshotExposedAccessibilityElement(in: root, label: AgentKind.claudeCode.displayName) == nil)
        let label = UILabel()
        label.accessibilityLabel = AgentKind.claudeCode.displayName
        label.isAccessibilityElement = false
        root.addSubview(label)
        #expect(snapshotExposedAccessibilityElement(in: root, label: AgentKind.claudeCode.displayName) == nil)

        root.accessibilityElements = [label]
        #expect(snapshotExposedAccessibilityElement(in: root, label: AgentKind.claudeCode.displayName) == nil)

        let proxy = UIAccessibilityElement(accessibilityContainer: root)
        proxy.accessibilityLabel = AgentKind.claudeCode.displayName
        root.accessibilityElements = [proxy]
        #expect(snapshotExposedAccessibilityElement(in: root, label: AgentKind.claudeCode.displayName) === proxy)
    }

    @Test func externalPopoverAXEvidenceRejectsEmptyStaleAndUnrelatedTrees() throws {
        let request = SnapshotExternalAXRequest(
            nonce: "parser-fixture-nonce", scene: "UsagePopDT", phase: "awaitingAXProof",
            pid: 42, udid: "parser-fixture-udid", windowTitle: "Phlox parser fixture",
            requestedAt: 1_000, nativeContentSizeCategory: "AX5", proofFile: "unused-parser-fixture"
        )
        // Parser契約の人工fixture。実測AX証拠として撮影側へ渡さない。
        let rawTree = """
        Window: "Phlox parser fixture", App: Simulator.
        1 text Description: Claude Code
        2 text Description: Codex
        3 text Description: Cursor
        """
        let payload: [String: Any] = [
            "nonce": request.nonce, "scene": request.scene, "phase": "presentedAX",
            "pid": request.pid, "udid": request.udid, "windowTitle": request.windowTitle,
            "capturedAt": 1_001, "rawAXTree": rawTree,
        ]
        func parse(_ changes: [String: Any]) throws -> Set<String> {
            let data = try JSONSerialization.data(withJSONObject: payload.merging(changes) { _, new in new })
            let evidence = try JSONDecoder().decode(SnapshotExternalAXEvidence.self, from: data)
            return try evidence.validatedLabels(for: request, now: 1_002)
        }
        let labels = try parse([:])
        try SnapshotExternalAXEvidence.validateUsageLayout(labels: labels, isAccessibilitySize: true)
        let invalidProofs: [[String: Any]] = [
            ["rawAXTree": ""], ["nonce": "old-run"], ["scene": "ReplyDT"], ["pid": 43],
            ["udid": "other-simulator"], ["phase": "awaitingTap"], ["capturedAt": 999],
            ["windowTitle": "Other Simulator"], ["rawAXTree": "Window: \"Other Simulator\", App: Simulator.\n1 text Description: Claude Code"],
            ["rawAXTree": "Window: \"Phlox parser fixture\", App: Simulator.\n1 button Description: Claude Code、Codex、Cursor"],
        ]
        for change in invalidProofs {
            #expect(throws: SnapshotExternalAXValidationError.self) { try parse(change) }
        }
        #expect(throws: SnapshotExternalAXValidationError.self) {
            try SnapshotExternalAXEvidence.validateUsageLayout(labels: labels, isAccessibilitySize: false)
        }
        let columnTree = rawTree + "\n4 text Description: 枠\n5 text Description: 残り\n6 text Description: リセット"
        let columnLabels = try parse(["rawAXTree": columnTree])
        try SnapshotExternalAXEvidence.validateUsageLayout(labels: columnLabels, isAccessibilitySize: false)
        #expect(throws: SnapshotExternalAXValidationError.self) {
            try SnapshotExternalAXEvidence.validateUsageLayout(labels: columnLabels, isAccessibilitySize: true)
        }
    }

    @Test func thinkingPreviewExpandsVerticallyAtAccessibilitySize() throws {
        let locale = Locale(identifier: "ja_JP")
        func height<Content: View>(_ content: Content) throws -> CGFloat {
            let host = UIHostingController(rootView:
                content
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.locale, locale)
                    .frame(width: 320)
            )
            host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 2_000)
            host.view.layoutIfNeeded()
            try #require(host.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
            return host.sizeThatFits(in: CGSize(width: 320, height: 2_000)).height
        }
        let preview = "ProxyRouter の転送処理と既存テストを確認しています。失敗したテストの原因を調べ、修正方針をまとめています。"
        let referenceHeight = try height(VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(AgentActivityState.thinking.orbLabel(locale: locale))
                .font(DSFont.sessionDetailSubtitle.italic())
            Text(preview)
                .font(DSFont.iosCaption2)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading))
        let fullHeight = try height(DSThinkingIndicator(state: .thinking, reasoningPreview: preview))
        let shortHeight = try height(DSThinkingIndicator(state: .thinking, reasoningPreview: "確認中"))
        #expect(referenceHeight > 0)
        #expect(abs(fullHeight - referenceHeight) < 1,
                "The actual indicator must fit the same full text as a native AX5 reference stack")
        #expect(fullHeight > shortHeight, "A longer preview must add lines instead of being truncated")
        print("thinking AX5 width=320 heights: reference=\(referenceHeight), actual=\(fullHeight), short=\(shortHeight)")
    }

    @Test func sendFailureFixtureUsesCatalogAndPreservesDraft() async throws {
        let session = Session(id: "send-failure-fixture", name: "fixture", agent: .claudeCode, status: .idle, updatedAt: .distantPast)
        let api = SessionDetailSnapshotAPI(
            session: session, messages: .success([]), approvals: [], turnUsage: nil,
            readiness: nil, sendFailure: .unreachable
        )
        let attachment = SendAttachment(mediaType: "image/png", data: snapshotAttachmentData(color: .systemGray))
        let model = try await failedSendSnapshotModel(session: session, api: api, text: "失敗した指示", attachments: [attachment])
        let presentation = try #require(model.sendErrorPresentation)
        #expect(presentation.title == "送信できませんでした")
        #expect(presentation.cause == "本文と添付は入力欄に戻しました。")
        #expect(presentation.nextStep == "送信ボタンで送り直せます。")
        #expect(presentation.technicalDetail == PhloxError.unreachable.presentation.technicalDetail)
        #expect(model.inputText == "失敗した指示")
        #expect(model.attachmentItems.map(\.send) == [attachment])
        #expect(!model.isSending)
    }

    private func failedSendSnapshotModel(
        session: Session,
        api: SessionDetailSnapshotAPI,
        text: String,
        attachments: [SendAttachment] = []
    ) async throws -> SessionDetailViewModel {
        let model = SessionDetailViewModel(session: session, api: api)
        model.addAttachments(attachments)
        model.inputText = text
        model.inputCursorUTF16 = text.utf16.count
        await model.sendMessage()
        try #require(model.sendErrorPresentation != nil, "Send failure scenes must use the public send path and catalog presentation")
        return model
    }

    private func renderSessionDetailSnapshots(output: URL, osSuffix: String, selectedScenes: Set<String>? = nil) async throws {
        let detailName = osSuffix == "-ios18" ? "Detail18" : "Detail"
        let snapshotDate = Date(timeIntervalSince1970: 1_792_300_000)
        let chatName = "refactor: ControlServer proxy"
        let detailSession = Session(
            id: "stage6-detail", name: "add /approvals endpoint", agent: .codex,
            status: .awaitingApproval(prompt: "git rm ControlServer.swift"),
            projectName: "Phlox", statusEnteredAt: Date().addingTimeInterval(-120), updatedAt: snapshotDate
        )
        let detailRecentMessages: [ChatMessage] = [
            .reasoning(id: "detail-reason", text: "# 方針\n/approvals は ControlServer が受けている。\n契約 v2 の id・session・kind・prompt を返す。\n既存のルーティングとテストを確認する。"),
            .agent(id: "detail-agent-1", text: "既存のルーティングとテストを確認してから実装します。"),
            .command(id: "detail-tool-1", command: "Read Router.swift", output: "GET /approvals → ProxyRouter"),
            .command(id: "detail-tool-2", command: "Read ControlServer.swift", output: ""),
            .command(id: "detail-tool-3", command: "rg -n approvals Sources", output: ""),
            .command(id: "detail-tool-4", command: "Read Package.swift", output: ""),
            .command(id: "detail-tool-5", command: "Read MobileProxy.swift", output: ""),
            .command(id: "detail-tests", command: "swift test --package-path ios/Packages/PhloxKit", output: "Test run with 50 tests in 2 suites passed after 1.2 seconds."),
            .fileChange(id: "detail-file", changes: [
                ChatFileChange(path: "Sources/ControlServer/ProxyRouter.swift", diff: "@@ -0,0 +1,128 @@\n+public struct ProxyRouter {\n+    public func forward(_ request: Request) async throws -> Response {\n+        try await upstream.send(request)\n+    }\n+}", kind: "edit"),
                ChatFileChange(path: "Sources/ControlServer/ControlServer.swift", diff: "@@ -87,41 +87,0 @@\n-router.get(\"/sessions/*\") { try await self.forwardLegacy($0) }\n-router.get(\"/approvals\") { try await self.forwardLegacy($0) }", kind: "edit"),
            ]),
            .agent(id: "detail-agent-2", text: "新しいルータに置き換えるため、旧 ControlServer.swift の削除が必要です。"),
        ]

        func chatSession(
            _ id: String,
            _ status: SessionStatus,
            stalled: Bool = false
        ) -> Session {
            Session(
                id: id, name: chatName, agent: .claudeCode, status: status,
                projectName: "Phlox", isStalled: stalled,
                statusEnteredAt: stalled ? Date().addingTimeInterval(-192) : nil,
                updatedAt: snapshotDate
            )
        }

        let testCommand = "swift test --package-path macos/Packages/ControlServer"
        let buildCommand = "swift build --package-path macos/Packages/ControlServer"
        let testOutputLines = ["Exit code 1"] + (1...48).map { index in
            index == 11
                ? "✘ ProxyRouterTests.testForwardsApprovals — XCTAssertEqual failed: (\"502\") is not equal to (\"200\")"
                : "✔ ProxyRouterTests.testCase\(index) passed"
        } + ["Test Suite 'ProxyRouterTests' finished"]
        let testOutput = testOutputLines.joined(separator: "\n")
        let userFirst = ChatMessage.user(
            id: "chat-user",
            text: "/sessions の転送を ControlServer から MobileProxy 側の ProxyRouter に寄せて。既存のテストは全部通すこと。502 の画面も添付する"
        )
        let reasoning = ChatMessage.reasoning(
            id: "chat-reasoning",
            text: "# 方針\nControlServer.swift と MobileProxy の両方に /sessions の転送がある。\n片方に寄せるなら、認証ヘッダを扱っている MobileProxy 側が自然。\nまず既存テストで転送の振る舞いを固定してから移す。"
        )
        let readCommands: [ChatMessage] = [
            .command(id: "chat-tool-1", command: "Read ControlServer.swift", output: "router.get(\"/sessions/*\") { try await self.forwardLegacy($0) }"),
            .command(id: "chat-tool-2", command: "rg -n forward macos/Packages", output: "ControlServer.swift:88: router.get(\"/sessions/*\") { try await self.forwardLegacy($0) }"),
        ]
        let agent = ChatMessage.agent(
            id: "chat-agent-1",
            text: "転送処理が `ControlServer` と `MobileProxy` の 2 か所にあります。`ProxyRouter` を新設して 1 か所にまとめます。"
        )
        let subAgent = ChatMessage.subAgent(
            id: "chat-subagent",
            text: "Sub-agent explore-map completed: 既存テストの棚卸し"
        )
        let fileA = ChatMessage.fileChange(id: "chat-file-a", changes: [
            ChatFileChange(path: "ControlServer/ProxyRouter.swift", diff: "@@ -0,0 +1,8 @@\n+import Foundation\n+\n+public struct ProxyRouter {\n+    let upstream: URL\n+    public func handler(_ request: Request) async throws -> Response {\n+        try await forward(request, to: upstream.appending(path: request.path))\n+    }\n+}", kind: "create"),
        ])
        let fileB = ChatMessage.fileChange(id: "chat-file-b", changes: [
            ChatFileChange(
                path: "ControlServer/ControlServer.swift",
                diff: "@@ -87,3 +87,2 @@\n-router.get(\"/sessions/*\") { try await self.forwardLegacy($0) }\n-router.get(\"/approvals\") { try await self.forwardLegacy($0) }\n+server.mount(\"/sessions\", ProxyRouter(upstream: upstream).handler)\n router.get(\"/usage\") { try await self.usage($0) }",
                kind: "edit"
            ),
        ])
        let lastToolCommands: [ChatMessage] = [
            .command(id: "chat-tool-edit", command: "Edit ProxyRouter.swift", output: ""),
            .command(id: "chat-tool-grep", command: "rg -n forwardLegacy macos/Packages", output: ""),
            .command(id: "chat-tool-tests", command: testCommand, output: testOutput),
        ]
        let buildMessage = ChatMessage.command(id: "chat-build", command: buildCommand, output: "実行中…")
        let expandedReasoning = ChatMessage.reasoning(
            id: "chat-reasoning-expanded",
            text: "ProxyRouter に /approvals も載せる。\n認証ヘッダは MobileProxy で付け直しているので、ルーターでは触らない。\n先に testForwardsApprovals を書いて、落ちることを確かめてから実装する。"
        )
        let richReply = ChatMessage.agent(
            id: "chat-rich-reply",
            text: "### 変更点\n\n- `ProxyRouter` を新設し、/sessions と /approvals の転送をまとめた\n- ControlServer からは転送処理を削除\n- 既存テスト 50 件はすべて成功\n\n経緯は [ADR 0044](#adr-0044) にまとめました。呼び出し側はこう変わります。\n\n```swift\nlet router = ProxyRouter(upstream: config.upstream)\nserver.mount(\"/sessions\", router.handler)\nserver.mount(\"/approvals\", router.handler)\n```\n\n| エンドポイント | 変更前 | 変更後 | テスト |\n| --- | --- | --- | --- |\n| /sessions/* | ControlServer | ProxyRouter | 12 件 成功 |\n| /approvals | ControlServer | ProxyRouter | 8 件 成功 |\n| /usage | MobileProxy | MobileProxy | 変更なし |"
        )
        let finalLintReply = ChatMessage.agent(
            id: "chat-lint-reply",
            text: "lint の指摘 3 件を直しました。テストと lint はすべて通っています。"
        )
        let commandFailure = ChatMessage.error(
            id: "chat-error",
            message: "swift test が終了コード 1 で失敗しました: ProxyRouterTests.testForwardsApprovals2 — XCTAssertEqual failed: (\"502\") is not equal to (\"200\")"
        )
        let runningMessages = [userFirst, reasoning] + readCommands + [agent, subAgent, fileA, fileB] + lastToolCommands + [buildMessage]
        let runningBlockCount = SessionDetailToolCallGrouping.visibleSlice(
            from: runningMessages,
            blockLimit: Int.max
        ).blocks.count
        let tailPadding = (0..<max(0, 50 - runningBlockCount)).map { index in
            ChatMessage.agent(id: "chat-long-tail-\(index)", text: "ProxyRouter の変更を確認しています。")
        }
        let olderMessages = (0..<412).map { index in
            if index.isMultiple(of: 2) {
                ChatMessage.user(id: "chat-long-old-user-\(index)", text: "以前の作業を確認してください。")
            } else {
                ChatMessage.agent(id: "chat-long-old-agent-\(index)", text: "前の作業記録です。")
            }
        }
        let longChatMessages = olderMessages + runningMessages + tailPadding
        let stallMessages = [userFirst, reasoning] + readCommands + [agent, fileA, fileB] + lastToolCommands + [buildMessage]
        let idleMessages = [fileA, fileB] + lastToolCommands + [richReply, .turnCost(id: "chat-turn-cost", costUSD: 0.42)]
        let doneMessages: [ChatMessage] = [
            richReply,
            .turnCost(id: "chat-first-turn-cost", costUSD: 0.42),
            .user(id: "chat-lint-request", text: "ありがとう。最後に lint も通して"),
            .command(id: "chat-lint", command: "swiftlint lint --strict", output: "Exit code 0\nok"),
            .fileChange(id: "chat-lint-file", changes: [ChatFileChange(path: "ControlServer/ProxyRouter.swift", diff: "@@ -1,3 +1,3 @@\n-old one\n-old two\n-old three\n+new one\n+new two\n+new three", kind: "edit")]),
            finalLintReply,
            .turnCost(id: "chat-done-turn-cost", costUSD: 0.16),
        ]
        let chatErrorMessages: [ChatMessage] = [
            agent, subAgent, fileA, fileB,
            .command(id: "chat-error-tests", command: testCommand, output: "Exit code 1\nProxyRouterTests failed"),
            commandFailure,
        ]
        let approval = Approval(
            id: "stage6-approval", sessionID: detailSession.id, kind: .codex,
            prompt: "旧 ControlServer.swift を削除して続行します（新しいルータに置き換え済み）。",
            actionKind: "command"
        )
        let answeredScope = ChatMessage.userQuestion(
            id: "answered-scope", requestId: "scope-request",
            questions: [UserQuestionItem(
                question: "/approvals のレスポンス契約は v2 で進めますか？", header: "SCOPE",
                options: [
                    UserQuestionOption(label: "v2", description: "id・session・kind・prompt を含む"),
                    UserQuestionOption(label: "v1 のまま", description: "既存クライアントに合わせる"),
                ], multiSelect: false
            )],
            answers: ["/approvals のレスポンス契約は v2 で進めますか？": ["v2"]], state: .answered
        )
        let pendingDeploymentQuestion = ChatMessage.userQuestion(
            id: "pending-deploy-test", requestId: "deploy-test-request",
            questions: [
                UserQuestionItem(
                    question: "どの環境で動作確認しますか？", header: "DEPLOY",
                    options: [
                        UserQuestionOption(label: "staging", description: "検証環境"),
                        UserQuestionOption(label: "prod", description: "本番環境"),
                    ], multiSelect: false
                ),
                UserQuestionItem(
                    question: "失敗している 3 件のテストはどう扱いますか？", header: "TEST",
                    options: [], multiSelect: false
                ),
            ],
            answers: ["どの環境で動作確認しますか？": ["staging"]], state: .pending
        )
        let pendingDeploymentQuestionFail = ChatMessage.userQuestion(
            id: "pending-deploy-fail", requestId: "deploy-test-request",
            questions: [
                UserQuestionItem(
                    question: "どの環境で動作確認しますか？", header: "DEPLOY",
                    options: [
                        UserQuestionOption(label: "staging", description: "検証環境"),
                        UserQuestionOption(label: "prod", description: "本番環境"),
                    ], multiSelect: false
                ),
                UserQuestionItem(
                    question: "マージ前に何を実行しますか？", header: "CHECKS",
                    options: [UserQuestionOption(label: "lint"), UserQuestionOption(label: "unit tests"), UserQuestionOption(label: "UI tests")],
                    multiSelect: true
                ),
            ],
            answers: [
                "どの環境で動作確認しますか？": ["staging"],
                "マージ前に何を実行しますか？": ["lint", "unit tests"],
            ], state: .pending
        )
        let plainQuestion = ChatMessage.userQuestion(
            id: "plain-question", requestId: "plain-question-request",
            questions: [UserQuestionItem(
                question: "/approvals のレスポンス契約は v2（id・session・kind・prompt を含む）で進めますか？",
                header: "CONTRACT", options: [], multiSelect: false
            )],
            answers: nil, state: .pending
        )
        let replyToolPermission = ChatMessage.userQuestion(
            id: "reply-tool-permission", requestId: "reply-tool-request",
            questions: [UserQuestionItem(
                question: "旧 ControlServer.swift を削除します（ProxyRouter に置き換え済み）。",
                header: "Bash",
                options: [UserQuestionOption(label: "Allow"), UserQuestionOption(label: "Deny")],
                multiSelect: false, toolName: "Bash", toolDetail: "git rm ControlServer.swift", allowsSessionScope: true
            )],
            answers: nil, state: .pending
        )
        let replyEditPermission = ChatMessage.userQuestion(
            id: "reply-edit-permission", requestId: "reply-edit-request",
            questions: [UserQuestionItem(
                question: "ControlServer.swift を編集しますか？",
                header: "Edit",
                options: [UserQuestionOption(label: "Allow"), UserQuestionOption(label: "Deny")],
                multiSelect: false, toolName: "Edit", toolDetail: "Sources/ControlServer/ControlServer.swift"
            )],
            answers: nil, state: .pending
        )
        let replySession = Session(
            id: "stage6-reply", name: chatName, agent: .claudeCode,
            status: .awaitingUserQuestion, projectName: "Phlox",
            statusEnteredAt: Date().addingTimeInterval(-120), updatedAt: snapshotDate
        )
        let replyMessages: [ChatMessage] = [
            .command(id: "reply-git-status", command: "git status --short", output: "Exit code 0"),
            .agent(id: "reply-explanation", text: "旧 ControlServer.swift は ProxyRouter に置き換わったため、削除が必要です。"),
            replyToolPermission,
            replyEditPermission,
        ]
        let codexReplyMessages: [ChatMessage] = [
            .command(id: "reply-codex-status", command: "git status --short", output: "Exit code 0"),
            .agent(id: "reply-codex-explanation", text: "テストが通ったので、リモートのブランチを更新します。"),
        ]
        let codexApprovalOne = Approval(
            id: "reply-codex-one", sessionID: detailSession.id, kind: .codex,
            prompt: "git push --force-with-lease origin feature/proxy-router", actionKind: "command"
        )
        let codexDiffApproval = Approval(
            id: "reply-approval-diff", sessionID: detailSession.id, kind: .codex,
            prompt: "Sources/ControlServer/ProxyRouter.swift ほか 1 件", actionKind: "fileChange"
        )
        let codexDiffMessage = ChatMessage.fileChange(id: "reply-approval-diff", changes: [
            ChatFileChange(
                path: "Sources/ControlServer/ProxyRouter.swift",
                diff: "@@ -41,3 +41,4 @@\n func register(_ app: Application) {\n     app.get(\"health\", use: health)\n-    legacy.mount(on: app)\n+    app.get(\"approvals\", use: list)\n+    app.post(\"approvals\", \":id\", use: respond)\n+    app.get(\"sessions\", use: sessions)\n }",
                kind: "edit"
            ),
            ChatFileChange(
                path: "Sources/ControlServer/ControlServer.swift",
                diff: "@@ -87,4 +87,1 @@\n-router.get(\"/sessions/*\") { try await self.forwardLegacy($0) }\n-router.get(\"/approvals\") { try await self.forwardLegacy($0) }\n-router.get(\"/usage\") { try await self.usage($0) }\n+server.mount(\"/sessions\", ProxyRouter(upstream: upstream).handler)",
                kind: "edit"
            ),
        ])
        let usage42 = TurnUsage(costUSD: 0.42, contextUsedTokens: 44_000, contextWindowTokens: 200_000)
        let usage16 = TurnUsage(costUSD: 0.16, contextUsedTokens: 62_000, contextWindowTokens: 200_000)
        let replyInputText = "ProxyRouterTests の失敗 3 件を先に直して。\n直したら swift test をもう一度流して、結果だけ教えて"
        let replyIdleMessages: [ChatMessage] = [
            .command(id: "reply-tests-ok", command: testCommand, output: "Exit code 0\n50 tests passed"),
            .agent(id: "reply-idle", text: "テストは 50 件すべて成功しました。次は何をしますか？"),
            .turnCost(id: "reply-idle-cost", costUSD: 0.42),
        ]
        // Mac と同じく、実行中のコマンドを会話の最後に置く。
        let replyRunningMessages: [ChatMessage] = [
            .agent(id: "reply-run", text: "ProxyRouter を追加しました。テストを実行します。"),
            .command(id: "reply-running-tests", command: testCommand, output: "実行中…"),
        ]
        let replyQuestionIntro: [ChatMessage] = [
            .command(id: "reply-question-tests", command: testCommand, output: "Exit code 0\n50 tests passed"),
            .agent(id: "reply-question-intro", text: "テストは通りました。次に進む前に 2 点確認させてください。"),
        ]
        let replyDeploymentQuestion = ChatMessage.userQuestion(
            id: "reply-deploy-checks", requestId: "deploy-test-request",
            questions: [
                UserQuestionItem(
                    question: "どの環境で動作確認しますか？", header: "DEPLOY",
                    options: [UserQuestionOption(label: "staging", description: "検証環境"), UserQuestionOption(label: "prod", description: "本番環境")],
                    multiSelect: false
                ),
                UserQuestionItem(
                    question: "マージ前に何を実行しますか？", header: "CHECKS",
                    options: [UserQuestionOption(label: "lint"), UserQuestionOption(label: "unit tests"), UserQuestionOption(label: "UI tests")],
                    multiSelect: true
                ),
            ],
            answers: ["どの環境で動作確認しますか？": ["staging"]], state: .pending
        )
        let flowRunningSession = Session(
            id: detailSession.id, name: detailSession.name, agent: .codex, status: .running,
            projectName: "Phlox", updatedAt: snapshotDate
        )
        let attachmentPreviews = [
            snapshotAttachmentData(color: .systemOrange, label: "502"),
            snapshotAttachmentData(color: .systemBlue, label: "LOG"),
        ]
        var cases: [SessionDetailSnapshotCase] = [
            .init(name: detailName, session: detailSession, messages: .success(detailRecentMessages), approvals: [approval]),
            .init(name: "ChatLoading", session: chatSession("loading", .running), messages: .suspended),
            .init(name: "ChatEmpty", session: chatSession("empty", .idle), messages: .success([])),
            .init(name: "ChatFetchErr", session: chatSession("fetch-error", .running), messages: .failure(.server(status: 502, message: "gateway timeout"))),
            .init(name: "ChatUnsupported", session: Session(id: "pty", name: chatName, agent: .claudeCode, status: .running, backend: "pty", updatedAt: snapshotDate), messages: .success(stallMessages)),
            .init(name: "ChatSendFail", session: chatSession("send-failed", .idle), messages: .success([lastToolCommands[0], lastToolCommands[1], lastToolCommands[2], richReply]), inputText: "失敗しているテストを先に直して", sendFailure: .unreachable),
            .init(name: "Chat", session: chatSession("chat", .running), messages: .success(runningMessages), attachmentPreviews: ["chat-user": attachmentPreviews], statusAge: 38),
            .init(name: "ChatLong", session: chatSession("chat-long", .running), messages: .success(longChatMessages), statusAge: 38, startsAtTop: true),
            .init(
                name: "ChatSub",
                session: Session(
                    id: "sub-agent", name: "サブエージェント", agent: .claudeCode,
                    status: .running, projectName: "Phlox", backend: "explore-map", updatedAt: snapshotDate
                ),
                messages: .success([
                    .user(id: "sub-user", text: "ControlServer と MobileProxy のテストを一覧にして、転送に関わるものに印を付けて"),
                    .reasoning(id: "sub-reasoning", text: "テストファイルを検索し、転送処理を扱うテストを見分けます。"),
                    .command(id: "sub-command", command: "rg --files -g \"*Tests.swift\"", output: "50 件のテストファイルを確認しました。"),
                    .agent(id: "sub-agent-result", text: "テストは 2 パッケージで合計 50 件です。転送に関わるものに ★ を付けました。\n\n- ★ ProxyRouterTests.testForwardsSessions\n- ★ ProxyRouterTests.testForwardsApprovals\n- AuthTests.testRejectsExpiredToken\n\n- ★ LegacyForwardTests.testKeepsAuthHeader\n- UsageTests.testReturnsLimits\n\n以上 50 件。★ は 14 件です。"),
                ]),
                statusAge: 28
            ),
            .init(name: "DraftCreated", session: Session(id: "draft-created", name: "Lotus", agent: .claudeCode, status: .running, projectName: "Phlox", updatedAt: snapshotDate), messages: .success([.user(id: "draft-created-user", text: "ProxyRouter のテストを流して、落ちたら直して")]), isNewSession: true, permission: "manual"),
            .init(name: "ChatStall", session: chatSession("stalled", .running, stalled: true), messages: .success(stallMessages), attachmentPreviews: ["chat-user": attachmentPreviews]),
            .init(name: "ChatIdle", session: chatSession("idle", .idle), messages: .success(idleMessages), usage: usage42),
            .init(name: "ChatDone", session: chatSession("done", .completed(exitCode: 0)), messages: .success(doneMessages), usage: usage16),
            .init(name: "ChatError", session: chatSession("error", .error(message: "ProxyRouterTests failed")), messages: .success(chatErrorMessages)),
            .init(name: "ChatQuestion", session: chatSession("question", .awaitingUserQuestion), messages: .success([answeredScope, agent, .command(id: "question-tests", command: testCommand, output: testOutput), .error(id: "question-error", message: "3 件のテストが失敗しています（ProxyRouterTests）。"), pendingDeploymentQuestion]), statusAge: 12),
            .init(name: "ChatExpandCmd", session: chatSession("expand-cmd", .running), messages: .success([agent] + lastToolCommands + [buildMessage]), expandedMessageIDs: ["chat-tool-edit", "chat-tool-tests"], statusAge: 12),
            .init(name: "ChatExpandDiff", session: chatSession("expand-diff", .idle), messages: .success([agent, fileA, fileB, .turnCost(id: "chat-turn-cost", costUSD: 0.42)]), usage: usage42, expandedMessageIDs: ["chat-file-a-file-0", "chat-file-b-file-0"]),
            .init(name: "ChatThinking", session: chatSession("thinking", .running), messages: .success([userFirst, reasoning, readCommands[0], readCommands[1], agent, expandedReasoning]), attachmentPreviews: ["chat-user": attachmentPreviews], expandedMessageIDs: ["chat-reasoning-expanded"], statusAge: 12),
            .init(name: "ReplyStarting", session: chatSession("starting", .starting), messages: .success([.command(id: "starting-command", command: "phlox spawn --agent claude-code --project ControlServer", output: "実行中"), .agent(id: "starting-message", text: "セッションを準備しています。")]), isNewSession: true),
            .init(name: "ReplyEmpty", session: chatSession("reply-empty", .idle), messages: .success(replyIdleMessages), usage: usage42),
            .init(name: "ReplyTyping", session: chatSession("reply-typing", .idle), messages: .success(replyIdleMessages), usage: usage42, inputText: replyInputText),
            .init(name: "ReplyHaiku", session: chatSession("reply-haiku", .idle), messages: .success(replyIdleMessages), usage: usage42, inputText: replyInputText, modelName: "Haiku 5.5"),
            .init(name: "ReplyModel", session: chatSession("reply-model", .idle), messages: .success(replyIdleMessages), usage: usage42, showsModelPicker: true),
            .init(name: "ChatRename", session: chatSession("chat-rename", .running), messages: .success(runningMessages), statusAge: 38, showsRename: true),
            .init(name: "ReplyRunEmpty", session: chatSession("reply-run-empty", .running), messages: .success(replyRunningMessages), statusAge: 38),
            .init(name: "ReplyRunText", session: chatSession("reply-run-text", .running), messages: .success(replyRunningMessages), statusAge: 38, inputText: replyInputText),
            .init(name: "ReplyDone", session: chatSession("reply-done", .completed(exitCode: 0)), messages: .success([.command(id: "reply-lint", command: "swiftlint lint --strict", output: "Exit code 0\nok"), finalLintReply, .turnCost(id: "reply-done-cost", costUSD: 0.42)]), usage: usage42),
            .init(name: "ReplyError", session: chatSession("reply-error", .error(message: "API Error: 529 overloaded_error")), messages: .success([.command(id: "reply-error-tests", command: testCommand, output: "Exit code 1\nProxyRouterTests failed"), .agent(id: "reply-error-explanation", text: "swift test が終了コード 1 で失敗しました。失敗したテストを調べます。"), .error(id: "reply-api-error", message: "API Error: 529 overloaded_error"), .turnCost(id: "reply-error-cost", costUSD: 0.42)]), usage: usage42),
            .init(name: "Reply", session: replySession, messages: .success(replyMessages), statusAge: 120),
            .init(name: "ReplyCodex", session: detailSession, messages: .success(codexReplyMessages), approvals: [codexApprovalOne], statusAge: 120),
            .init(name: "ReplyApprovalDiff", session: detailSession, messages: .success([codexDiffMessage]), approvals: [codexDiffApproval], statusAge: 60, replyState: .expandedApprovalDiff),
            .init(name: "ReplyApprovalFail", session: replySession, messages: .success(replyMessages), statusAge: 120, replyState: .approvalFailure),
            .init(name: "ReplyDT", session: replySession, messages: .success(replyMessages), statusAge: 120, isAccessibilitySize: true),
            .init(name: "FlowApprove", session: detailSession, messages: .success(detailRecentMessages), approvals: [Approval(id: approval.id, sessionID: detailSession.id, kind: .codex, prompt: "git rm ControlServer.swift", actionKind: "command")], statusAge: 120),
            .init(name: "FlowNext", session: flowRunningSession, messages: .success(detailRecentMessages + [.command(id: "flow-git-rm", command: "git rm ControlServer.swift", output: "実行中…")]), statusAge: 3, replyState: .approvalResult(actionLabel: "許可", remainingCount: 1, nextSessionName: "Tulip", nextIsQuestion: true)),
            .init(name: "ReplyQuestion", session: chatSession("reply-question", .awaitingUserQuestion), messages: .success(replyQuestionIntro + [replyDeploymentQuestion]), statusAge: 12),
            .init(name: "ReplyQuestionPlain", session: chatSession("reply-question-plain", .awaitingUserQuestion), messages: .success(replyQuestionIntro + [plainQuestion]), statusAge: 12),
            .init(name: "ReplyQuestionFail", session: chatSession("reply-question-fail", .awaitingUserQuestion), messages: .success(replyQuestionIntro + [pendingDeploymentQuestionFail]), statusAge: 12, replyState: .questionFailure(requestID: "deploy-test-request")),
        ]

        let baseCases = cases
        let detailVariants: [(base: String, name: String, width: CGFloat, height: CGFloat, dark: Bool, ax5: Bool)] = [
            ("ChatEmpty", "ReplyCompactAX5", 428, 926, false, true),
            ("ChatEmpty", "ReplyCompactAX5SE", 375, 667, false, true),
            ("ReplyCodex", "ReplyKeyboardAX5", 428, 926, false, true),
            ("ReplyCodex", "ReplyKeyboardAX5SE", 375, 667, false, true),
            ("Chat", "ChatDark", 428, 926, true, false),
            ("Chat", "ChatDT", 428, 926, false, true),
            ("Chat", "ChatSE", 375, 667, false, false),
            ("Chat", "ChatSEDark", 375, 667, true, false),
            ("ChatError", "ChatErrorDark", 428, 926, true, false),
            ("ChatExpandCmd", "ChatExpandCmdDT", 428, 926, false, true),
            ("ChatExpandCmd", "ChatExpandCmdDark", 428, 926, true, false),
            ("ChatExpandDiff", "ChatExpandDiffDark", 428, 926, true, false),
            ("ChatFetchErr", "ChatFetchErrDark", 428, 926, true, false),
            ("ChatIdle", "ChatIdleDark", 428, 926, true, false),
            ("ChatQuestion", "ChatQuestionDark", 428, 926, true, false),
            ("ChatSendFail", "ChatSendFailDark", 428, 926, true, false),
            ("ChatSendFail", "ChatSendFailAX5", 428, 926, false, true),
            ("ChatSendFail", "ChatSendFailAX5SE", 375, 667, false, true),
            ("ChatStall", "ChatStallDT", 428, 926, false, true),
            ("ChatStall", "ChatStallDark", 428, 926, true, false),
            ("ChatSub", "ChatSubDark", 428, 926, true, false),
            ("ChatThinking", "ChatThinkingDark", 428, 926, true, false),
            ("ChatUnsupported", "ChatUnsupportedDark", 428, 926, true, false),
            (detailName, "DetailDT", 428, 926, false, true),
            (detailName, "DetailDark", 428, 926, true, false),
            (detailName, "DetailSE", 375, 667, false, false),
            (detailName, "ListTapDetail", 428, 926, false, false),
            ("Reply", "ReplyApprovalDark", 428, 926, true, false),
            ("ReplyApprovalDiff", "ReplyApprovalDiffDT", 428, 926, false, true),
            ("ReplyApprovalDiff", "ReplyApprovalDiffDark", 428, 926, true, false),
            ("ReplyApprovalDiff", "ReplyApprovalDiffSE", 375, 667, false, false),
            ("ReplyApprovalFail", "ReplyApprovalFailDark", 428, 926, true, false),
            ("Reply", "ReplyApprovalSEDark", 375, 667, true, false),
            ("Reply", "ReplySE", 375, 667, false, false),
            ("ReplyTyping", "ReplySEDark", 375, 667, true, false),
            ("ReplyEmpty", "ReplyDark", 428, 926, true, false),
            ("ReplyQuestion", "ReplyQuestionDT", 428, 926, false, true),
            ("ReplyQuestion", "ReplyQuestionDark", 428, 926, true, false),
            ("ReplyQuestion", "ReplyQuestionSE", 375, 667, false, false),
        ]
        for variant in detailVariants {
            guard var snapshot = baseCases.first(where: { $0.name == variant.base }) else {
                throw SnapshotError.bodyDidNotRender
            }
            snapshot.name = variant.name
            snapshot.width = variant.width
            snapshot.height = variant.height
            snapshot.isDark = variant.dark
            snapshot.isAccessibilitySize = variant.ax5
            if ["ReplyKeyboardAX5", "ReplyKeyboardAX5SE"].contains(variant.name) {
                snapshot.inputText = "承認前にこの変更を確認してください"
                snapshot.approvals = [Approval(id: "keyboard-approval", sessionID: snapshot.session.id, kind: .codex,
                    prompt: "git push --force-with-lease origin feature/proxy-router", actionKind: "command")]
            }
            cases.append(snapshot)
        }
        // 同名の場面でPNGを上書きし、別の状態を撮れたように見せない。
        try #require(Set(cases.map(\.name)).count == cases.count)
        if let selectedScenes {
            let unknown = selectedScenes.subtracting(Set(cases.map(\.name)))
            try #require(unknown.isEmpty, "Unknown detail scenes: \(unknown.sorted())")
        }

        let environment = AppEnvironment.uiTesting(scenario: .goldenPath)
        let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
        await list.observe()
        defer { list.stop() }

        for snapshot in cases {
            guard selectedScenes?.contains(snapshot.name) ?? true else { continue }
            let themeID = AppearancePreference.system.themeID(
                systemColorScheme: snapshot.isDark ? .dark : .light
            )
            UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)

            let session = snapshot.session.isStalled || snapshot.statusAge != nil
                ? Session(
                    id: snapshot.session.id, name: snapshot.session.name, agent: snapshot.session.agent,
                    status: snapshot.session.status, needsAttention: snapshot.session.needsAttention,
                    subtitle: snapshot.session.subtitle, projectId: snapshot.session.projectId,
                    projectName: snapshot.session.projectName, backend: snapshot.session.backend,
                    isStalled: snapshot.session.isStalled, hasUnseenCompletion: snapshot.session.hasUnseenCompletion,
                    parentSessionId: snapshot.session.parentSessionId,
                    statusEnteredAt: Date().addingTimeInterval(-(snapshot.statusAge ?? 192)), updatedAt: snapshot.session.updatedAt
                )
                : snapshot.session
            let readiness = SessionDetailSnapshotReadiness()
            let api = SessionDetailSnapshotAPI(
                session: session, messages: snapshot.messages, approvals: snapshot.approvals,
                turnUsage: snapshot.usage,
                readiness: readiness, modelName: snapshot.modelName, permission: snapshot.permission,
                sendFailure: snapshot.sendFailure
            )
            let preparedModel: SessionDetailViewModel?
            if snapshot.sendFailure != nil {
                preparedModel = try await failedSendSnapshotModel(session: session, api: api, text: snapshot.inputText)
                if ["ChatSendFailAX5", "ChatSendFailAX5SE"].contains(snapshot.name) {
                    try #require(preparedModel?.inputText == snapshot.inputText, "AX5 failure scenes must preserve the submitted draft")
                }
            } else {
                preparedModel = nil
            }
            let navigationState = SessionNavigationState.resolve(
                listState: list.state, lastKnownSessions: list.lastKnownSessions, reachability: .online
            )
            let size = CGSize(width: snapshot.width, height: snapshot.height)
            let keyboardProbe = ["ReplyKeyboardAX5", "ReplyKeyboardAX5SE"].contains(snapshot.name) ? SnapshotRealKeyboardProbe() : nil
            defer { keyboardProbe?.stop() }
            let compactApproval: ReplyApproval? = ["ReplyCompactAX5", "ReplyCompactAX5SE"].contains(snapshot.name)
                ? ReplyApproval.codex(approval: Approval(id: "compact-ax5", sessionID: session.id, kind: .codex,
                    prompt: "git push --force-with-lease origin feature/proxy-router", actionKind: "command"),
                    statusEnteredAt: snapshotDate, chatMessages: []) : nil
            let detailHost = SessionDetailSnapshotHost(
                list: list, navigationState: navigationState, snapshot: snapshot,
                session: session, api: api, preparedModel: preparedModel
            )
            let snapshotUsage = UsageViewModel(
                api: api, agents: UITestUsageFixtures.values(for: .normal), state: .loaded,
                lastSuccessfulAt: UITestUsageFixtures.asOfDate, now: { UITestUsageFixtures.asOfDate }
            )
            let content = Group {
                if let compactApproval {
                    ScrollView {
                        ReplyApprovalCard(approval: compactApproval, result: nil, index: 0, count: 1,
                            isResponding: false, isKeyboardVisible: true, onDecision: { _ in },
                            onPrevious: {}, onNext: {}, onShowNext: {})
                            .padding(16)
                    }
                    .background(IOSColor.bg.base)
                } else {
                    detailHost
                }
            }
            .environment(\.usageViewModel, snapshotUsage)
            .environment(\.colorScheme, snapshot.isDark ? .dark : .light)
            .environment(\.dynamicTypeSize, snapshot.isAccessibilitySize ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: size.width)

            let image = try await windowImage(
                content, size: size,
                safeArea: snapshot.width == 428
                    ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
                scale: 2, dark: snapshot.isDark, scenarioID: snapshot.name, settleDelay: .milliseconds(800),
                waitUntilReady: {
                    if compactApproval != nil { return }
                    switch snapshot.messages {
                    case .suspended:
                        if session.agent == .codex {
                            await readiness.waitForApprovals()
                        }
                    case .success, .failure:
                        if snapshot.session.isPTY { return }
                        await readiness.waitForMessages()
                        if session.agent == .codex {
                            await readiness.waitForApprovals()
                        }
                    }
                    if snapshotExpectsApproval(snapshot) {
                        try await readiness.waitForApprovalVisible()
                        await Task.yield()
                        FileHandle.standardError.write(Data("[approval arming \(snapshot.name)] real card ready; wait \(ReplyApprovalPolicy.armDelay)s.begin\n".utf8))
                        try await Task.sleep(for: .seconds(ReplyApprovalPolicy.armDelay))
                        FileHandle.standardError.write(Data("[approval arming \(snapshot.name)] wait.end\n".utf8))
                    }
                },
                prepareWindow: (["ChatSendFailAX5", "ChatSendFailAX5SE"].contains(snapshot.name) || compactApproval != nil || keyboardProbe != nil) ? { window in
                    if let keyboardProbe {
                        let approval = ReplyApproval.codex(approval: try #require(snapshot.approvals.first),
                            statusEnteredAt: snapshotDate, chatMessages: [])
                        try await verifyRealKeyboardReply(window, probe: keyboardProbe, approval: approval,
                            usageViewModel: snapshotUsage, draft: snapshot.inputText, scene: snapshot.name, output: output, osSuffix: osSuffix)
                    } else if let compactApproval {
                        try await verifyCompactApprovalAX5(window, approval: compactApproval, scene: snapshot.name,
                                                          output: output, osSuffix: osSuffix)
                    } else {
                        let model = try #require(preparedModel)
                        let failure: ErrorPresentation = try #require(model.sendErrorPresentation)
                        try await verifyAX5FailureComposer(window, presentation: failure,
                            draft: snapshot.inputText, scene: snapshot.name, output: output, osSuffix: osSuffix)
                    }
                } : nil
            )
            try writeSnapshot(
                image, name: "\(snapshot.name)-\(Int(snapshot.width))x\(Int(snapshot.height))-\(snapshot.isDark ? "dark" : "light")\(snapshot.isAccessibilitySize ? "-ax5" : "")\(osSuffix).png", to: output,
                expectedSize: size, expectedScale: 2
            )
        }
    }

    private func snapshotExpectsApproval(_ snapshot: SessionDetailSnapshotCase) -> Bool {
        guard !snapshot.session.isPTY else { return false }
        switch snapshot.session.agent {
        case .codex: return !snapshot.approvals.isEmpty
        case .claudeCode:
            guard case .success(let messages) = snapshot.messages else { return false }
            return messages.contains { message in
                guard case let .userQuestion(_, _, questions, _, .pending) = message else { return false }
                return ReplyApproval.isClaudeToolPermissionQuestion(questions)
            }
        case .cursor: return false
        }
    }

    @Test func approvalSnapshotWaitMatchesActualViewModel() async {
        let permission = UserQuestionItem(
            question: "コマンドを実行しますか？", header: "Bash", options: [], multiSelect: false,
            toolName: "Bash", toolDetail: "swift test", allowsSessionScope: true
        )
        let question = UserQuestionItem(question: "どちらを使いますか？", header: "Question", options: [], multiSelect: false)
        let pendingPermission = ChatMessage.userQuestion(id: "permission", requestId: "permission", questions: [permission], answers: nil, state: .pending)
        let answeredPermission = ChatMessage.userQuestion(id: "answered", requestId: "answered", questions: [permission], answers: [:], state: .answered)
        let pendingQuestion = ChatMessage.userQuestion(id: "ask", requestId: "ask", questions: [question], answers: nil, state: .pending)
        let inputs: [(AgentKind, [ChatMessage], Bool, Bool)] = [
            (.claudeCode, [pendingPermission], false, true),
            (.claudeCode, [pendingQuestion], false, false),
            (.claudeCode, [answeredPermission], false, false),
            (.codex, [], true, true),
            (.cursor, [pendingPermission], false, false),
        ]
        for (agent, messages, hasCodexApproval, expected) in inputs {
            let session = Session(id: "arming", name: "arming", agent: agent, status: .awaitingUserQuestion, updatedAt: Date())
            let approvals = hasCodexApproval ? [Approval(id: "a", sessionID: session.id, kind: .codex, prompt: "swift test", actionKind: "command")] : []
            let snapshot = SessionDetailSnapshotCase(name: "arming", session: session, messages: .success(messages), approvals: approvals)
            let api = SessionDetailSnapshotAPI(session: session, messages: .success(messages), approvals: approvals, turnUsage: nil, readiness: nil)
            let model = SessionDetailViewModel(session: session, api: api)
            await model.load()
            await model.loadApprovals()
            #expect((model.currentReplyApproval != nil) == expected)
            #expect(snapshotExpectsApproval(snapshot) == expected)
        }
    }

    private func renderNarrowScreenSnapshots(output: URL, osSuffix: String, selectedScenes: Set<String>) async throws {
        try await renderPairSettingsSnapshots(output: output, osSuffix: osSuffix, selectedScenes: selectedScenes)
        for name in ["ShellSE", "ListSE"] where selectedScenes.contains(name) {
            let themeID = AppearancePreference.system.themeID(systemColorScheme: .light)
            UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: name == "ShellSE" ? .sessionShell : .listSE)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            defer { list.stop() }
            let navigationState = SessionNavigationState.resolve(
                listState: list.state, lastKnownSessions: list.lastKnownSessions, reachability: .online
            )
            let content = AppShellView(
                selection: .constant(.sessions), navigationState: navigationState,
                reachability: .online, lastFetchedAt: list.lastFetchedAt, host: "100.64.0.1",
                hidesTabBar: false, hidesAccessory: false,
                onOpenSession: { _ in }, onShowSessionList: {}, onReconnect: {}
            ) {
                NavigationStack {
                    SessionListView(
                        viewModel: list, reachability: .online, endpoint: "100.64.0.1:8765",
                        onSelectDetail: { _ in }, onAddSession: { _ in }, initialExpandedSessionIDs: ["refactor"]
                    )
                }.dsCampNavigationChrome()
            } settings: {
                EmptyView()
            }
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            let size = CGSize(width: 375, height: 667)
            let image = try await windowImage(
                content.frame(width: size.width), size: size,
                safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
                scale: 2, dark: false, scenarioID: name
            )
            try writeSnapshot(image, name: "\(name)-375x667-light\(osSuffix).png", to: output, expectedSize: size, expectedScale: 2)
        }
    }

    private func renderPairSettingsSnapshots(output: URL, osSuffix: String, selectedScenes: Set<String>? = nil) async throws {
        let pairScenes: [(name: String, width: CGFloat, height: CGFloat, dark: Bool, ax5: Bool)] = [
            ("Pair", 428, 926, false, false), ("PairDark", 428, 926, true, false),
            ("PairDT", 428, 926, false, true), ("PairSE", 375, 667, false, false),
            ("PairSEDark", 375, 667, true, false), ("PairNoCam", 428, 926, false, false),
            ("PairApplying", 428, 926, false, false), ("PairRescanDone", 428, 926, false, false),
            ("PairParseErr", 428, 926, false, false), ("PairParseErrDark", 428, 926, true, false),
            ("PairConnecting", 428, 926, false, false),
            ("PairConnectFail", 428, 926, false, false), ("PairConnectFailDT", 428, 926, false, true),
            ("PairConnectFailDark", 428, 926, true, false), ("PairUnreach", 428, 926, false, false),
            ("PairTestFail", 428, 926, false, false), ("PairTestFailDark", 428, 926, true, false),
            ("PairTestOk", 428, 926, false, false), ("PairTesting", 428, 926, false, false),
            ("PairSettings", 428, 926, false, false), ("PairGate", 428, 926, false, false),
            ("PairGateDark", 428, 926, true, false), ("PairGateFail", 428, 926, false, false),
            ("PairGateFailAX5", 428, 926, false, true), ("PairGateFailAX5SE2", 375, 667, false, true),
        ]
        let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

        for scene in pairScenes {
            guard selectedScenes?.contains(scene.name) ?? true else { continue }
            let themeID = AppearancePreference.system.themeID(systemColorScheme: scene.dark ? .dark : .light)
            UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let tokenStore = InMemoryTokenStore(token: "snapshot-token")
            let configStore = InMemoryConnectionConfigStore(
                ["PairSettings", "PairTestFail", "PairTestFailDark", "PairTestOk", "PairTesting", "PairUnreach"].contains(scene.name)
                    ? config : nil
            )
            let connection = ConnectionSettingsViewModel(
                tokenStore: tokenStore,
                configStore: configStore,
                probe: { _, _ in true }
            )
            switch scene.name {
            case "PairTestFail", "PairTestFailDark":
                connection.banner = .failure(ConnectionSettingsCopy.testFailureMessage)
                connection.seedReachabilityForSnapshot(false)
            case "PairTestOk":
                connection.banner = .success(ConnectionSettingsCopy.testSuccessMessage)
                connection.seedReachabilityForSnapshot(true)
            case "PairTesting":
                connection.isTesting = true
                connection.seedReachabilityForSnapshot(true)
            case "PairSettings":
                connection.seedReachabilityForSnapshot(true)
            default:
                break
            }

            let content: AnyView
            var listToStop: SessionListViewModel?
            switch scene.name {
            case "PairGate", "PairGateDark", "PairGateFail", "PairGateFailAX5", "PairGateFailAX5SE2":
                let gate = LaunchGateViewModel(authenticator: StubAuthenticator(allows: false))
                if ["PairGateFail", "PairGateDark", "PairGateFailAX5", "PairGateFailAX5SE2"].contains(scene.name) {
                    gate.state = .failed("認証できませんでした")
                }
                content = AnyView(LaunchGateView(viewModel: gate, onUnlocked: {}, automaticallyAuthenticates: false))
            case "PairConnecting":
                content = AnyView(ConnectingOverlayView(
                    failure: nil,
                    deviceName: "Ryosuke's Mac",
                    endpoint: "100.64.0.1:8765",
                    elapsedSeconds: 8,
                    onRetry: {}, onDismiss: {}
                ))
            case "PairConnectFail", "PairConnectFailDT", "PairConnectFailDark":
                content = AnyView(ConnectingOverlayView(
                    failure: ConnectFailure(
                        title: "Mac から一覧を読み込めませんでした",
                        message: "接続先は保存しました。20 秒待っても Mac から応答がありません。",
                        nextStep: "Mac で次の 3 つを確かめてから、再試行してください。",
                        detail: "GET http://100.64.0.1:8765/sessions · 20 秒で無応答",
                        checklist: [
                            "Mac がスリープしていない",
                            "Mac で Phlox が起動している",
                            "Mac と iPhone の Tailscale がオンになっている",
                        ]
                    ),
                    deviceName: "Ryosuke's Mac",
                    endpoint: "100.64.0.1:8765",
                    elapsedSeconds: 20,
                    onRetry: {}, onDismiss: {}
                ))
            case "PairApplying", "PairRescanDone", "PairParseErr", "PairParseErrDark", "PairNoCam", "PairUnreach":
                let apply = PairingApplyViewModel(tokenStore: tokenStore, configStore: configStore, probe: { _, _ in true })
                if scene.name == "PairApplying" {
                    apply.seedPhaseForSnapshot(.applying, connection: config)
                } else if scene.name == "PairUnreach" {
                    apply.seedPhaseForSnapshot(.unreachable(guidance: PairingCopy.unreachableGuidance), connection: config)
                } else if scene.name == "PairRescanDone" {
                    apply.seedPhaseForSnapshot(
                        .success(name: "Ryosuke's Mac"),
                        connection: ConnectionConfig(host: "100.64.0.7", port: 8765)
                    )
                }
                let scannedString: String? = switch scene.name {
                case "PairParseErr": "phlox://pair?v=1&port=8765&token=\(String(repeating: "a", count: 64))"
                case "PairParseErrDark": "phlox://pair?v=1&host=100.64.0.1&port=8765&token=invalid"
                default: nil
                }
                content = AnyView(NavigationStack {
                    QRScanScreen(
                        applyViewModel: apply,
                        initialScannedString: scannedString,
                        isReconnection: scene.name == "PairRescanDone",
                        previousEndpoint: scene.name == "PairRescanDone" ? "100.64.0.1:8765" : nil
                    )
                }.dsCampNavigationChrome())
            case "PairSettings", "PairTestFail", "PairTestFailDark", "PairTestOk", "PairTesting":
                let environment = AppEnvironment.uiTesting(scenario: .empty)
                let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
                await list.observe()
                listToStop = list
                let navigationState = SessionNavigationState.resolve(
                    listState: list.state,
                    lastKnownSessions: list.lastKnownSessions,
                    reachability: .online
                )
                content = AnyView(
                    AppShellView(
                        selection: .constant(.settings),
                        navigationState: navigationState,
                        reachability: .online,
                        lastFetchedAt: list.lastFetchedAt,
                        host: "100.64.0.1",
                        hidesTabBar: false,
                        hidesAccessory: true,
                        onOpenSession: { _ in },
                        onShowSessionList: {},
                        onReconnect: {}
                    ) {
                        NavigationStack {
                            SessionListView(
                                viewModel: list,
                                reachability: .online,
                                onSelectDetail: { _ in },
                                onAddSession: { _ in }
                            )
                        }.dsCampNavigationChrome()
                    } settings: {
                        NavigationStack {
                            PairConnectionSettingsSnapshotView(
                                connectionViewModel: connection,
                                onQRScan: {}
                            )
                        }.dsCampNavigationChrome()
                    }
                    .frame(width: scene.width)
                )
            default:
                content = AnyView(NavigationStack {
                    ConnectionSettingsView(viewModel: connection, onQRScan: {})
                }.dsCampNavigationChrome())
            }
            let size = CGSize(width: scene.width, height: scene.height)
            let safeArea = scene.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let image = try await windowImage(
                content.environment(\.colorScheme, scene.dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, scene.ax5 ? .accessibility5 : .large)
                    .environment(\.locale, Locale(identifier: "ja_JP")),
                size: size, safeArea: safeArea, scale: 2, dark: scene.dark, scenarioID: scene.name
            )
            try writeSnapshot(
                image,
                name: "\(scene.name)-\(Int(scene.width))x\(Int(scene.height))-\(scene.dark ? "dark" : "light")\(scene.ax5 ? "-ax5" : "")\(osSuffix).png",
                to: output, expectedSize: size, expectedScale: 2
            )
            listToStop?.stop()
        }

        let settingsScenes: [(name: String, width: CGFloat, height: CGFloat, dark: Bool, ax5: Bool)] = [
            ("SetUse", 428, 926, false, false), ("SetDark", 428, 926, true, false),
            ("SetDT", 428, 926, false, true), ("SetSE", 375, 667, false, false),
            ("SetSEDark", 375, 667, true, false), ("SetDisc", 428, 926, false, false),
            ("SetDiscDark", 428, 926, true, false), ("FlowUsage", 428, 926, false, false),
        ]
        for scene in settingsScenes {
            guard selectedScenes?.contains(scene.name) ?? true else { continue }
            let disconnected = scene.name == "SetDisc" || scene.name == "SetDiscDark"
            let reachability: Reachability = disconnected ? .unreachableHost : .online
            let themeID = AppearancePreference.system.themeID(systemColorScheme: scene.dark ? .dark : .light)
            UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let environment = disconnected
                ? AppEnvironment.uiTesting(scenario: .empty)
                : AppEnvironment.uiTesting(scenario: .goldenPath, screen: .sessionShell)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            let navigationState = SessionNavigationState.resolve(
                listState: list.state, lastKnownSessions: list.lastKnownSessions, reachability: reachability
            )
            let settings = AppSettings(store: InMemoryAppSettingsStore(
                faceIDEnabled: scene.name != "FlowUsage",
                notificationsEnabled: true,
                appearance: scene.name == "SetDark" ? .dark : .system
            ))
            let connection = ConnectionSettingsViewModel(
                tokenStore: environment.tokenStore,
                configStore: InMemoryConnectionConfigStore(ConnectionConfig(host: "100.64.0.1", port: 8765)),
                probe: { _, _ in true }
            )
            if scene.name == "SetDisc" || scene.name == "SetDiscDark" {
                connection.seedReachabilityForSnapshot(false)
            } else if scene.name != "FlowUsage" {
                connection.seedReachabilityForSnapshot(true)
            }
            let content = AppShellView(
                selection: .constant(.settings), navigationState: navigationState,
                reachability: reachability,
                lastFetchedAt: reachability == .online ? list.lastFetchedAt : Date().addingTimeInterval(-180),
                host: "100.64.0.1",
                hidesTabBar: false, hidesAccessory: false,
                onOpenSession: { _ in }, onShowSessionList: {}, onReconnect: {}
            ) {
                NavigationStack {
                    SessionListView(viewModel: list, reachability: .online, onSelectDetail: { _ in }, onAddSession: { _ in })
                }.dsCampNavigationChrome()
            } settings: {
                NavigationStack {
                    SettingsView(
                        viewModel: SettingsViewModel(settings: settings),
                        connectionViewModel: connection,
                        onQRScan: {},
                        biometricTypeOverride: scene.width == 375 ? .touchID : nil,
                        reachability: scene.name == "SetDisc" || scene.name == "SetDiscDark" ? .unreachableHost : .online,
                        lastFetchedAt: scene.name == "SetDisc" || scene.name == "SetDiscDark"
                            ? Date().addingTimeInterval(-180)
                            : Date()
                    )
                }.dsCampNavigationChrome()
            }
            .environment(\.colorScheme, scene.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, scene.ax5 ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: scene.width)

            let size = CGSize(width: scene.width, height: scene.height)
            let safeArea = scene.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let image = try await windowImage(content, size: size, safeArea: safeArea, scale: 2, dark: scene.dark, scenarioID: scene.name)
            try writeSnapshot(
                image,
                name: "\(scene.name)-\(Int(scene.width))x\(Int(scene.height))-\(scene.dark ? "dark" : "light")\(scene.ax5 ? "-ax5" : "")\(osSuffix).png",
                to: output, expectedSize: size, expectedScale: 2
            )
            list.stop()
        }
    }

    private func renderGlanceSnapshots(output: URL, osSuffix: String) async throws {
        for dark in [false, true] {
            let samples: [SharedSessionSummary?] = SessionGlanceState.allCases.map { state in
                SharedSessionSummary(
                    id: state.rawValue, statusLabel: state.label, title: "refactor: ControlServer proxy",
                    detail: "phlox", updatedAt: Date().addingTimeInterval(-120), displayState: state.rawValue
                )
            } + [nil]
            let widgets = VStack(spacing: 16) {
                ForEach(samples.indices, id: \.self) { index in
                    HStack(spacing: 28) {
                        Text(samples[index]?.glanceState.rawValue ?? "empty")
                            .font(.caption).frame(width: 90, alignment: .leading)
                        SessionStatusWidgetView(summary: samples[index])
                            .padding(14).frame(width: 170, height: 170)
                            .background(GlanceStyle.card(dark: dark), in: RoundedRectangle(cornerRadius: 24))
                        SessionStatusWidgetView(summary: samples[index], rectangular: true)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(width: 172, height: 76)
                            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(24)
            .frame(width: 560, height: 2080)
            .background(GlanceStyle.color(dark ? 0x0B0B0D : 0xECECF1))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            let widgetSize = CGSize(width: 560, height: 2080)
            let widgetImage = try await windowImage(widgets, size: widgetSize, safeArea: .zero, scale: 2, dark: dark, scenarioID: "glanceWidgets")
            try writeSnapshot(widgetImage, name: "glanceWidgets-\(dark ? "dark" : "light")\(osSuffix).png",
                              to: output, expectedSize: widgetSize, expectedScale: 2)

            let codes = ["session_completed", "approval_pending", "question_pending", "session_error",
                         "session_stalled", "session_exited", "future"]
            let activities = VStack(spacing: 18) {
                ForEach(codes, id: \.self) { code in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(code).font(.caption)
                        SessionLiveActivityView(state: .init(
                            sessionId: "snapshot", sessionName: "refactor: ControlServer proxy", status: code,
                            summary: code == "future" ? "Mac から届いた未知の状態の補足" : SessionGlanceState(activityStatus: code).label
                        ))
                        .frame(width: 404)
                        .background(GlanceStyle.card(dark: dark).opacity(0.82), in: RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            .padding(24).frame(width: 452, height: 1060)
            .background(GlanceStyle.color(dark ? 0x0B0B0D : 0xECECF1))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            let activitySize = CGSize(width: 452, height: 1060)
            let activityImage = try await windowImage(activities, size: activitySize, safeArea: .zero, scale: 2, dark: dark, scenarioID: "glanceLiveActivity")
            try writeSnapshot(activityImage, name: "glanceLiveActivity-\(dark ? "dark" : "light")\(osSuffix).png",
                              to: output, expectedSize: activitySize, expectedScale: 2)
        }
    }

    private func outputDirectory(variables: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if let path = variables["PHLOX_SNAPSHOT_DIR"] {
            try #require(path.hasPrefix("/"), "PHLOX_SNAPSHOT_DIR must be absolute")
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return root.appendingPathComponent(".verification/ios-redesign/snapshots", isDirectory: true)
    }

    private func renderNewChatSnapshots(
        output: URL,
        variables: [String: String],
        osSuffix: String,
        selectedScenes: Set<String>? = nil
    ) async throws {
        struct Layout {
            let name: String
            let width: CGFloat
            let height: CGFloat
            let dark: Bool
            let ax5: Bool
        }

        let layouts = [
            Layout(name: "Draft", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftFromProject", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftSuggest", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftEntryEmpty", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftPermDanger", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftPermDangerCodex", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftMoreSE", width: 375, height: 667, dark: false, ax5: false),
            Layout(name: "DraftMoreDT", width: 428, height: 926, dark: false, ax5: true),
            Layout(name: "DraftSpawning", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftSending", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftCreating", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftCreatingDark", width: 428, height: 926, dark: true, ax5: false),
            Layout(name: "DraftFailed", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftFailedAX5", width: 428, height: 926, dark: false, ax5: true),
            Layout(name: "DraftFailedAX5SE", width: 375, height: 667, dark: false, ax5: true),
            Layout(name: "DraftSE", width: 375, height: 667, dark: false, ax5: false),
            Layout(name: "DraftSEDark", width: 375, height: 667, dark: true, ax5: false),
            Layout(name: "DraftDT", width: 428, height: 926, dark: false, ax5: true),
            Layout(name: "DraftDark", width: 428, height: 926, dark: true, ax5: false),
        ]

        for layout in layouts {
            guard selectedScenes?.contains(layout.name) ?? true else { continue }
            let suiteName = "Phlox.NewChatSnapshot.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = NewChatSettingsStore(defaults: defaults)
            let selectedKind: AgentKind = layout.name == "DraftPermDangerCodex" ? .codex : .claudeCode
            store.record(
                kind: selectedKind,
                model: selectedKind == .codex ? "gpt-6.1-sol" : "sonnet",
                effort: "high",
                permission: selectedKind == .codex ? ":danger-full-access" : "manual",
                planMode: false,
                projectKey: layout.name == "DraftEntryEmpty" ? "deleted-project" : "project-phlox"
            )

            let entry: SessionComposeDraft = layout.name == "DraftFromProject"
                ? SessionComposeDraft(project: "SimpleBudget", projectID: "project-simple-budget")
                : SessionComposeDraft(project: "")
            let isAX5Failure = ["DraftFailedAX5", "DraftFailedAX5SE"].contains(layout.name)
            let spawnFailure = PhloxError.spawnRejected(reason: "workspace \"phlox\" is locked by another spawn")
            let api = NewChatSnapshotAPI(spawnFailure: isAX5Failure ? spawnFailure : nil)
            let viewModel = NewChatViewModel(api: api, entryProject: entry, settingsStore: store)
            await viewModel.load()

            let greeting: String = switch layout.name {
            case "DraftFromProject": "次は何を作りますか？"
            case "DraftSuggest": "今日の課題を教えてください"
            case "DraftEntryEmpty": "何をお手伝いしましょうか？"
            case "DraftSE", "DraftSEDark": "さあ、始めましょう"
            case "DraftDT": "アイデアを形にしましょう"
            case "DraftDark": "今日は何を進めますか？"
            case "DraftFailed", "DraftFailedAX5", "DraftFailedAX5SE": "さあ、始めましょう"
            default: "何から始めますか？"
            }
            var showsMoreSettings = false
            switch layout.name {
            case "DraftSuggest":
                viewModel.appendSuggestion(0)
            case "DraftEntryEmpty":
                viewModel.inputText = "README の手順を最新の CLI に合わせて直して"
                viewModel.inputCursorUTF16 = viewModel.inputText.utf16.count
                await viewModel.send { _, _ in }
            case "DraftPermDanger":
                viewModel.inputText = "CI の設定を直して、通るまで回して"
                viewModel.inputCursorUTF16 = viewModel.inputText.utf16.count
                viewModel.selectPermission("bypassPermissions")
            case "DraftPermDangerCodex":
                viewModel.inputText = "CI の設定を直して、通るまで回して"
                viewModel.inputCursorUTF16 = viewModel.inputText.utf16.count
                viewModel.selectPermission(":danger-full-access")
            case "DraftMoreSE", "DraftMoreDT":
                showsMoreSettings = true
            case "DraftCreating", "DraftCreatingDark":
                viewModel.seedProgressForSnapshot(text: "ProxyRouter のテストを流して、落ちたら直して", waitSeconds: 4)
            case "DraftSpawning":
                viewModel.seedProgressForSnapshot(text: "ProxyRouter のテストを流して、落ちたら直して", stage: .creating)
            case "DraftSending":
                viewModel.seedProgressForSnapshot(text: "ProxyRouter のテストを流して、落ちたら直して", stage: .sending)
            case "DraftFailed":
                viewModel.seedSpawnFailureForSnapshot(
                    reason: "workspace \"phlox\" is locked by another spawn",
                    text: "ProxyRouter のテストを流して、落ちたら直して"
                )
            case "DraftFailedAX5", "DraftFailedAX5SE":
                let draft = "ProxyRouter のテストを流して、落ちたら直して"
                viewModel.inputText = draft
                viewModel.inputCursorUTF16 = draft.utf16.count
                var created = false
                await viewModel.send { _, _ in created = true }
                try #require(!created && viewModel.creationErrorPresentation == spawnFailure.presentation,
                             "AX5 creation failure must use public send and the spawn-rejection catalog")
                try #require(viewModel.inputText == draft, "AX5 creation failure must preserve the submitted draft")
            default:
                break
            }

            let usage = UsageViewModel(api: api)
            await usage.load()
            let themeID = AppearancePreference.system.themeID(
                systemColorScheme: layout.dark ? .dark : .light
            )
            UserDefaults.standard.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)

            let size = CGSize(width: layout.width, height: layout.height)
            let content = NewChatSnapshotHost(
                viewModel: viewModel,
                usageViewModel: usage,
                greeting: greeting,
                dark: layout.dark,
                ax5: layout.ax5
            )
            .environment(\.colorScheme, layout.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, layout.ax5 ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: size.width)

            let safeArea = layout.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let scale: CGFloat = 2
            let image = try await windowImage(
                content,
                size: size,
                safeArea: safeArea,
                scale: scale,
                dark: layout.dark,
                scenarioID: layout.name,
                settleDelay: .milliseconds(100),
                prepareWindow: { window in
                    if isAX5Failure {
                        let failure: ErrorPresentation = try #require(viewModel.creationErrorPresentation)
                        try await verifyAX5FailureComposer(window, presentation: failure,
                            draft: viewModel.inputText, scene: layout.name, output: output, osSuffix: osSuffix)
                    }
                    if showsMoreSettings {
                        if variables["PHLOX_SNAPSHOT_EXTERNAL_MENU_ACTIVATION"] == "1" {
                            try await waitForExternalUsageActivation(window: window, output: output, sceneName: layout.name, requiresPopover: false)
                        } else {
                            let button = try #require(snapshotAccessibilityElement(in: window, label: "思考の強さと権限を変更"))
                            try #require(button.accessibilityActivate(), "Composer settings menu did not activate")
                        }
                    }
                }
            )
            try writeSnapshot(
                image,
                name: "\(layout.name)-\(Int(layout.width))x\(Int(layout.height))-\(layout.dark ? "dark" : "light")\(layout.ax5 ? "-ax5" : "")\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: scale
            )
        }
    }

    private func writeSnapshot(
        _ image: UIImage,
        name: String,
        to output: URL,
        expectedSize: CGSize,
        expectedScale: CGFloat
    ) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(hasBodyContent(image), "Blank or placeholder-only snapshot: \(name)")
        #expect(image.size == expectedSize)
        #expect(image.scale == expectedScale)
        #expect(image.cgImage?.width == Int(expectedSize.width * expectedScale))
        #expect(image.cgImage?.height == Int(expectedSize.height * expectedScale))
        let url = output.appendingPathComponent(name)
        let png = try #require(image.pngData())
        try png.write(to: url, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > 0)
        print("snapshot: \(url.path)")
    }

    /// 新しい2sceneだけ。本物inputへの公開focusと実OS通知を要求する。
    private func verifyRealKeyboardReply(_ window: UIWindow, probe: SnapshotRealKeyboardProbe, approval: ReplyApproval,
                                         usageViewModel: UsageViewModel, draft: String, scene: String, output: URL, osSuffix: String) async throws {
        @MainActor
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        @MainActor
        func frame(_ object: NSObject) -> CGRect { window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace) }
        func finite(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
        }
        let prefix = "\(scene)-\(Int(window.bounds.width))x\(Int(window.bounds.height))-ax5\(osSuffix)"
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        @MainActor
        func record(_ phase: String, extra: [String: Any] = [:]) throws {
            try JSONSerialization.data(withJSONObject: probe.state(window: window).merging(extra) { _, new in new }, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(prefix)-\(phase)-keyboard.json"))
        }
        do {
            let nativeInput = try #require(views(window).first {
                $0.window === window && (($0 as? UITextView)?.text == draft || ($0 as? UITextField)?.text == draft)
            }, "The actual rendered input must contain the fixture draft before focus")
            var ancestor = nativeInput.superview
            var outerScroll: UIScrollView?
            while let view = ancestor {
                if let scroll = view as? UIScrollView, scroll.window === window, scroll.isScrollEnabled,
                   scroll.bounds.width >= window.bounds.width * 0.7 { outerScroll = scroll }
                ancestor = view.superview
            }
            let focusScroll = try #require(outerScroll, "Real keyboard focus requires the actual input ancestor product scroll")
            let focusStability = SnapshotKeyboardFocusGeometryObserver(window: window, scroll: focusScroll, probe: probe, responder: nativeInput)
            focusStability.start()
            defer { focusStability.stop() }
            probe.start(responder: nativeInput)
            try record("before-focus")
            try #require(nativeInput.becomeFirstResponder(), "Public focus must succeed")
            let deadline = ContinuousClock.now + .seconds(5)
            while (!probe.didShowLocalKeyboard || !finite(probe.guideFrame(window: window)) || !focusStability.isStable) && ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            focusStability.stop()
            try record("after-focus", extra: ["focusScrollStability": focusStability.diagnostics])
            try #require(focusStability.isStable, "Actual input ancestor scroll must settle across three display frames within the original focus deadline")
            let keyboard = probe.guideFrame(window: window)
            try #require(nativeInput.isFirstResponder && probe.didShowLocalKeyboard && finite(keyboard)
                && window.bounds.intersects(keyboard), "A real local keyboard notification and keyboardLayoutGuide must both be observed")
            @MainActor
            func keyboardIsMaintained() -> Bool {
                let current = probe.guideFrame(window: window)
                return nativeInput.isFirstResponder && probe.didShowLocalKeyboard && !probe.localKeyboardHideObservedAfterShow
                    && finite(current) && abs(current.minX - keyboard.minX) <= 1 && abs(current.minY - keyboard.minY) <= 1
                    && abs(current.width - keyboard.width) <= 1 && abs(current.height - keyboard.height) <= 1
            }
            if ProcessInfo.processInfo.environment["PHLOX_SNAPSHOT_EXTERNAL_KEYBOARD_OBSERVATION"] == "1" {
                let variables = ProcessInfo.processInfo.environment
                let windowTitle = try #require(variables["PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE"] ?? variables["SIMULATOR_DEVICE_NAME"])
                let nonce = UUID().uuidString
                let proofFile = output.appendingPathComponent("\(scene)-\(nonce)-keyboard-observed.json")
                let request = SnapshotExternalAXRequest(nonce: nonce, scene: scene, phase: "awaitingKeyboardObservation",
                    pid: ProcessInfo.processInfo.processIdentifier, udid: try #require(variables["SIMULATOR_UDID"]),
                    windowTitle: windowTitle, requestedAt: Date().timeIntervalSince1970,
                    nativeContentSizeCategory: window.traitCollection.preferredContentSizeCategory.rawValue, proofFile: proofFile.path)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let identity = try #require(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
                try JSONSerialization.data(withJSONObject: identity.merging(probe.state(window: window)) { old, _ in old }, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("\(scene)-keyboard-ready.json"))
                let observationDeadline = ContinuousClock.now + .seconds(60)
                while !FileManager.default.fileExists(atPath: proofFile.path), ContinuousClock.now < observationDeadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                try #require(FileManager.default.fileExists(atPath: proofFile.path), "External keyboard observation was not supplied")
                let proof = try JSONDecoder().decode(SnapshotExternalAXEvidence.self, from: Data(contentsOf: proofFile))
                try #require(proof.nonce == nonce && proof.scene == scene && proof.phase == "keyboardObserved"
                    && proof.pid == request.pid && proof.udid == request.udid && proof.windowTitle == windowTitle)
                let now = Date().timeIntervalSince1970
                try #require(proof.capturedAt >= request.requestedAt && proof.capturedAt <= now + 5 && now - proof.capturedAt <= 120)
                try #require(proof.rawAXTree.components(separatedBy: .newlines).contains("Window: \"\(windowTitle)\", App: Simulator."))
            }
            let input = try #require(snapshotAccessibilityElement(in: window, label: "やりたいことを入力"))
            let send = try #require(snapshotAccessibilityElement(in: window, label: DSInputBar.sendAccessibilityLabel))
            let title = try #require(snapshotAccessibilityElement(in: window, label: approval.compactAccessibilityLabel))
            let show = try #require(snapshotAccessibilityElement(in: window, label: "表示"))
            let usageLabel = UsageRingPresentation.accessibilityLabel(agents: usageViewModel.presentationAgents,
                isRefreshing: usageViewModel.isRefreshing, isStale: usageViewModel.isStale, asOf: usageViewModel.asOfDate)
            let usage = try #require(snapshotAccessibilityElement(in: window, identifier: "UsageRingRow.button")
                ?? snapshotAccessibilityElement(in: window, label: usageLabel))
            @MainActor
            func measuredFrame(_ object: NSObject) -> CGRect {
                object === input ? nativeInput.convert(nativeInput.bounds, to: window) : frame(object)
            }
            let targets: [(object: NSObject, edge: String)] = [(title, "title-start"), (title, "title-end"),
                (show, "show"), (usage, "usage"), (input, "input"), (send, "send")]
            // 実祖先scrollが対象を包含する時だけ利用する。test側にscrollを追加しない。
            let ownedScrolls = views(window).compactMap { $0 as? UIScrollView }.filter {
                $0.window === window && $0.isScrollEnabled && $0.bounds.width >= window.bounds.width * 0.7
            }
            let root = try #require(window.rootViewController?.viewIfLoaded)
            @MainActor
            func visibleViewport(_ scroll: UIScrollView?) -> (rect: CGRect, diagnostics: [String: Any]) {
                let hostSafe = root.convert(root.safeAreaLayoutGuide.layoutFrame, to: window)
                let guide = probe.guideFrame(window: window)
                let keyboardRemaining = CGRect(x: hostSafe.minX, y: hostSafe.minY, width: hostSafe.width,
                    height: max(0, min(hostSafe.maxY, guide.minY) - hostSafe.minY))
                var visible = keyboardRemaining.intersection(window.bounds)
                var clips: [[String: Any]] = []
                let rawBoundsViewport = scroll.map { $0.convert($0.bounds, to: window) }
                let scrollViewport = scroll.map { $0.convert($0.bounds.inset(by: $0.adjustedContentInset), to: window) }
                if let scrollViewport { visible = visible.intersection(scrollViewport) }
                var ancestor = scroll?.superview
                while let view = ancestor {
                    if view.clipsToBounds {
                        let clip = view.convert(view.bounds, to: window)
                        clips.append(["class": String(reflecting: type(of: view)),
                            "identity": String(describing: ObjectIdentifier(view)), "frameInWindow": String(describing: clip)])
                        visible = visible.intersection(clip)
                    }
                    ancestor = view.superview
                }
                return (visible, ["actualScrollViewport": scrollViewport.map { String(describing: $0) } ?? "none",
                    "rawBoundsViewport": rawBoundsViewport.map { String(describing: $0) } ?? "none",
                    "adjustedInsets": scroll.map { String(describing: $0.adjustedContentInset) } ?? "none",
                    "insetViewport": scrollViewport.map { String(describing: $0) } ?? "none",
                    "ancestorClips": clips, "hostSafeViewport": String(describing: hostSafe),
                    "keyboardRemainingViewport": String(describing: keyboardRemaining), "visibleViewport": String(describing: visible)])
            }
            var finalSelectedScroll: UIScrollView?
            for (target, edge) in targets {
                var targetView: UIView? = target === input ? nativeInput : target as? UIView
                var container = target as? UIAccessibilityElement
                var containersSeen: Set<ObjectIdentifier> = []
                var containerChain: [[String: Any]] = [["class": String(reflecting: type(of: target)), "label": target.accessibilityLabel ?? ""]]
                while targetView == nil, let current = container, containersSeen.insert(ObjectIdentifier(current)).inserted {
                    containerChain.append(["class": String(reflecting: type(of: current)),
                        "containerClass": current.accessibilityContainer.map { String(reflecting: type(of: $0)) } ?? "none"])
                    targetView = current.accessibilityContainer as? UIView
                    container = current.accessibilityContainer as? UIAccessibilityElement
                }
                let beforeRect = measuredFrame(target)
                @MainActor
                func containsTarget(_ scroll: UIScrollView) -> Bool {
                    let content = CGRect(origin: .zero, size: scroll.contentSize).insetBy(dx: -1, dy: -1)
                    let rect = scroll.convert(measuredFrame(target), from: window)
                    return finite(content) && finite(rect) && content.contains(rect)
                }
                let directScroll = ownedScrolls.first { targetView?.isDescendant(of: $0) == true && containsTarget($0) }
                let inputAncestorScroll = ownedScrolls.filter { nativeInput.isDescendant(of: $0) && containsTarget($0) }
                    .min { $0.contentSize.height < $1.contentSize.height }
                let selectedScroll = directScroll ?? inputAncestorScroll
                finalSelectedScroll = selectedScroll
                let beforeViewport = visibleViewport(selectedScroll)
                let segmentHeight = min(beforeRect.height, beforeViewport.rect.height)
                let requested = edge == "title-start" ? CGRect(x: beforeRect.minX, y: beforeRect.minY, width: beforeRect.width, height: segmentHeight)
                    : edge == "title-end" ? CGRect(x: beforeRect.minX, y: beforeRect.maxY - segmentHeight, width: beforeRect.width, height: segmentHeight) : beforeRect
                let selectionMode = directScroll != nil ? "public-AX-container-ancestor" : inputAncestorScroll != nil ? "native-input-ancestor-and-target-content-containment" : "none"
                @MainActor
                func scrollDiagnostics() -> [[String: Any]] {
                    ownedScrolls.map { scroll in
                        ["identity": String(describing: ObjectIdentifier(scroll)), "class": String(reflecting: type(of: scroll)),
                         "frameInWindow": String(describing: scroll.convert(scroll.bounds, to: window)),
                         "bounds": String(describing: scroll.bounds), "contentSize": String(describing: scroll.contentSize),
                         "offset": String(describing: scroll.contentOffset), "adjustedInsets": String(describing: scroll.adjustedContentInset),
                         "nativeInputIsDescendant": nativeInput.isDescendant(of: scroll),
                         "targetViewIsDescendant": targetView?.isDescendant(of: scroll) ?? false,
                         "targetFrameInContent": String(describing: scroll.convert(measuredFrame(target), from: window)),
                         "containsFullTarget": containsTarget(scroll), "selected": scroll === selectedScroll,
                         "ownedWindow": scroll.window === window] as [String: Any]
                    }
                }
                try record("\(edge)-scroll-before", extra: ["targetClass": String(reflecting: type(of: target)),
                    "containerChain": containerChain, "targetViewClass": targetView.map { String(reflecting: type(of: $0)) } ?? "none",
                    "ownedScrolls": scrollDiagnostics(), "selectionMode": selectionMode,
                    "willAttemptPublicScroll": selectedScroll != nil, "requestedSegment": String(describing: requested),
                    "viewport": beforeViewport.diagnostics,
                    "rawAXTargetFrame": String(describing: frame(target)),
                    "measuredTargetFrame": String(describing: beforeRect),
                    "measurementMode": target === input ? "native-input-bounds-in-window" : "public-accessibility-frame"])
                try #require(finite(beforeViewport.rect), "The actual product scroll viewport must be finite and positive")
                if let scroll = selectedScroll {
                    scroll.scrollRectToVisible(scroll.convert(requested, from: window), animated: false)
                    window.layoutIfNeeded(); await Task.yield()
                }
                try record("\(edge)-scroll-after", extra: ["ownedScrolls": scrollDiagnostics(), "selectionMode": selectionMode,
                    "publicScrollAttempted": selectedScroll != nil, "targetFrameAfter": String(describing: measuredFrame(target)),
                    "rawAXTargetFrameAfter": String(describing: frame(target)),
                    "measurementMode": target === input ? "native-input-bounds-in-window" : "public-accessibility-frame"])
                let rect = measuredFrame(target)
                let afterViewport = visibleViewport(selectedScroll)
                let available = afterViewport.rect
                let observed = edge == "title-start" ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, available.height))
                    : edge == "title-end" ? CGRect(x: rect.minX, y: rect.maxY - min(rect.height, available.height), width: rect.width, height: min(rect.height, available.height)) : rect
                try record(edge, extra: ["label": target.accessibilityLabel ?? "", "targetFrame": String(describing: rect), "observedSegment": String(describing: observed), "remainingViewport": String(describing: available), "initialKeyboardGuideFrame": String(describing: keyboard), "viewport": afterViewport.diagnostics])
                try #require(keyboardIsMaintained(), "The original real keyboard guide must remain within 1pt at every post-scroll phase")
                try #require(finite(rect) && finite(available) && available.insetBy(dx: -1, dy: -1).contains(observed),
                    "Every real reply control must be reachable in the keyboard remaining viewport")
            }
            let inputFrame = measuredFrame(input), sendFrame = frame(send), titleFrame = frame(title), showFrame = frame(show)
            let finalViewport = visibleViewport(finalSelectedScroll)
            let available = finalViewport.rect
            try record("before-final-geometry", extra: ["initialKeyboardGuideFrame": String(describing: keyboard),
                "viewport": finalViewport.diagnostics, "inputFrame": String(describing: inputFrame), "sendFrame": String(describing: sendFrame),
                "rawAXInputFrame": String(describing: frame(input)), "inputMeasurementMode": "native-input-bounds-in-window"])
            try #require(keyboardIsMaintained(), "Keyboard dismissal must not make the final viewport appear larger")
            try #require(finite(available) && available.insetBy(dx: -1, dy: -1).contains(inputFrame)
                && available.insetBy(dx: -1, dy: -1).contains(sendFrame), "Input and send must remain reachable together")
            try #require(inputFrame.width >= 44 && inputFrame.height >= 44 && sendFrame.width >= 44 && sendFrame.height >= 44
                && showFrame.width >= 44 && showFrame.height >= 44)
            try #require(!inputFrame.intersects(sendFrame) && !titleFrame.intersects(showFrame)
                && !titleFrame.intersects(inputFrame), "Keyboard reply controls must not overlap")
            let reference = UIHostingController(rootView: Text(approval.compactTitle).font(DSFont.iosCaption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true).environment(\.dynamicTypeSize, .accessibility5))
            let natural = reference.sizeThatFits(in: CGSize(width: titleFrame.width, height: .greatestFiniteMagnitude))
            try #require(natural.height.isFinite && natural.height > 0 && titleFrame.height >= natural.height - 1)
            try record("verified")
        } catch {
            try record("failed")
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: output.appendingPathComponent("\(prefix)-keyboard-failure.png"))
            throw error
        }
    }

    /// isKeyboardVisible=trueは表示条件fixture。実キーボード操作の証明ではない。
    private func verifyCompactApprovalAX5(_ window: UIWindow, approval: ReplyApproval, scene: String,
                                          output: URL, osSuffix: String) async throws {
        @MainActor
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        @MainActor
        func frame(_ object: NSObject) -> CGRect {
            window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
        }
        func finite(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
        }
        let prefix = "\(scene)-\(Int(window.bounds.width))x\(Int(window.bounds.height))-ax5\(osSuffix)"
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            let title = try #require(snapshotAccessibilityElement(in: window, label: approval.compactAccessibilityLabel))
            let show = try #require(snapshotAccessibilityElement(in: window, label: "表示"))
            let scroll = try #require(views(window).compactMap { $0 as? UIScrollView }.first {
                $0.window === window && $0.isScrollEnabled && $0.bounds.width >= window.bounds.width * 0.7
            })
            let contentRect = scroll.convert(frame(title).union(frame(show)), from: window)
            try #require(finite(contentRect))
            scroll.scrollRectToVisible(contentRect, animated: false)
            window.layoutIfNeeded()
            await Task.yield()
            let titleFrame = frame(title), buttonFrame = frame(show)
            let root = try #require(window.rootViewController?.viewIfLoaded)
            let hostSafe = root.convert(root.safeAreaLayoutGuide.layoutFrame, to: window)
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
                .intersection(hostSafe)
            let reference = UIHostingController(rootView: Text(approval.compactTitle)
                .font(DSFont.iosCaption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.locale, Locale(identifier: "ja_JP")))
            try #require(finite(titleFrame))
            let natural = reference.sizeThatFits(in: CGSize(width: titleFrame.width, height: .greatestFiniteMagnitude))
            let state: [String: Any] = ["fixtureIsKeyboardVisible": true, "realKeyboardMeasured": false,
                "title": approval.compactTitle, "fullAXLabel": approval.compactAccessibilityLabel,
                "titleFrame": String(describing: titleFrame), "showButtonFrame": String(describing: buttonFrame),
                "viewport": String(describing: viewport), "naturalTitleSize": String(describing: natural),
                "windowSafeAreaInsets": String(describing: window.safeAreaInsets),
                "hostSafeAreaInsets": String(describing: root.safeAreaInsets), "hostSafeAreaFrame": String(describing: hostSafe),
                "scrollAdjustedInsets": String(describing: scroll.adjustedContentInset), "syntheticViewport": true,
                "scrollContent": String(describing: scroll.contentSize), "scrollOffset": String(describing: scroll.contentOffset)]
            try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(prefix)-geometry.json"))
            try #require(natural.height.isFinite && natural.height > 0 && titleFrame.height >= natural.height - 1,
                         "Compact approval must preserve the full natural AX5 title height")
            try #require(finite(buttonFrame) && buttonFrame.width >= 44 && buttonFrame.height >= 44)
            try #require(!titleFrame.intersects(buttonFrame), "Compact title and show action must not overlap")
            try #require(finite(viewport) && viewport.insetBy(dx: -1, dy: -1).contains(titleFrame)
                && viewport.insetBy(dx: -1, dy: -1).contains(buttonFrame), "Compact text and show action must be reachable together")
        } catch {
            let diagnosticDirectory = output.appendingPathComponent("r38-compact-public-ax", isDirectory: true)
            try FileManager.default.createDirectory(at: diagnosticDirectory, withIntermediateDirectories: true)
            var visited: Set<ObjectIdentifier> = []
            var nodes: [[String: Any]] = []
            @MainActor
            func visit(_ object: NSObject, parent: Int?, via: String) {
                guard visited.insert(ObjectIdentifier(object)).inserted else { return }
                let index = nodes.count
                let rect = frame(object)
                let count = object.accessibilityElementCount()
                nodes.append(["index": index, "parent": parent as Any? ?? NSNull(), "via": via,
                    "class": String(reflecting: type(of: object)), "label": object.accessibilityLabel ?? "",
                    "value": object.accessibilityValue ?? "", "isAccessibilityElement": object.isAccessibilityElement,
                    "identifier": (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier ?? "",
                    "traitsRaw": String(object.accessibilityTraits.rawValue), "frame": String(describing: rect),
                    "finitePositiveFrame": finite(rect), "containerCount": count == NSNotFound ? "NSNotFound" : String(count)])
                for child in object.accessibilityElements ?? [] {
                    if let child = child as? NSObject { visit(child, parent: index, via: "accessibilityElements") }
                }
                if count != NSNotFound && count > 0 {
                    for childIndex in 0..<count {
                        if let child = object.accessibilityElement(at: childIndex) as? NSObject {
                            visit(child, parent: index, via: "accessibilityElement(\(childIndex))")
                        }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews { visit(child, parent: index, via: "subviews") }
                }
            }
            visit(window, parent: nil, via: "owned-window")
            try JSONSerialization.data(withJSONObject: ["scene": scene, "expectedCompactAXLabel": approval.compactAccessibilityLabel,
                "canonicalTitle": approval.compactTitle, "nodeCount": nodes.count, "nodes": nodes], options: [.prettyPrinted, .sortedKeys])
                .write(to: diagnosticDirectory.appendingPathComponent("\(prefix)-failure-ax.json"))
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: output.appendingPathComponent("\(prefix)-failure.png"))
            throw error
        }
    }

    /// 新規AX5失敗4scene限定。公開scrollの到達検査であり指gestureの証明ではない。
    private func verifyAX5FailureComposer(_ window: UIWindow, presentation: ErrorPresentation?, draft: String,
                                         scene: String, output: URL, osSuffix: String, usageViewModel: UsageViewModel? = nil) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        @MainActor
        func objects(_ root: NSObject) -> [NSObject] {
            var seen: Set<ObjectIdentifier> = []
            @MainActor
            func visit(_ object: NSObject) -> [NSObject] {
                guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
                var children = (object.accessibilityElements ?? []).compactMap { $0 as? NSObject }
                let count = object.accessibilityElementCount()
                if count != NSNotFound && count > 0 {
                    children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
                }
                if let view = object as? UIView { children += view.subviews }
                return [object] + children.flatMap(visit)
            }
            return visit(root)
        }
        @MainActor
        func frame(_ object: NSObject) -> CGRect {
            window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
        }
        func finite(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
        }
        func rectJSON(_ rect: CGRect) -> [String: Any] {
            ["finitePositive": finite(rect), "description": String(describing: rect)]
        }
        let prefix = "\(scene)-\(Int(window.bounds.width))x\(Int(window.bounds.height))-ax5\(osSuffix)"
        var naturalMeasurements: [String: Any] = [:]
        @MainActor
        func record(_ phase: String) throws {
            let all = objects(window)
            let state: [String: Any] = ["phase": phase, "syntheticViewport": true, "window": rectJSON(window.bounds),
                "windowSafeAreaInsets": String(describing: window.safeAreaInsets),
                "hostSafeAreaInsets": String(describing: window.rootViewController?.viewIfLoaded?.safeAreaInsets),
                "naturalMeasurements": naturalMeasurements,
                "elements": all.filter { $0.accessibilityLabel != nil }.map {
                    ["label": $0.accessibilityLabel ?? "", "value": $0.accessibilityValue ?? "", "frame": rectJSON(frame($0))] as [String: Any]
                }, "scrolls": all.compactMap { $0 as? UIScrollView }.map {
                    ["class": String(reflecting: type(of: $0)), "viewport": rectJSON($0.convert($0.bounds.inset(by: $0.adjustedContentInset), to: window)),
                     "contentSize": String(describing: $0.contentSize), "offset": String(describing: $0.contentOffset),
                     "insets": String(describing: $0.adjustedContentInset), "ownedWindow": $0.window === window] as [String: Any]
                }]
            try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("\(prefix)-\(phase)-geometry.json"))
        }
        @MainActor
        func image(_ phase: String) throws {
            window.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: output.appendingPathComponent("\(prefix)-\(phase).png"))
        }
        window.layoutIfNeeded()
        await Task.yield()
        try record("initial")
        do {
            let all = objects(window)
            let input = try #require(snapshotAccessibilityElement(in: window, label: "やりたいことを入力"))
            let send = try #require(snapshotAccessibilityElement(in: window, label: DSInputBar.sendAccessibilityLabel))
            @MainActor
            func verifyComposer(in visible: CGRect) throws {
                let inputRect = frame(input), sendRect = frame(send)
                try #require(finite(visible) && finite(inputRect) && finite(sendRect))
                try #require(inputRect.width >= 44 && inputRect.height >= 44 && sendRect.width >= 44 && sendRect.height >= 44)
                try #require(visible.insetBy(dx: -1, dy: -1).contains(inputRect) && visible.insetBy(dx: -1, dy: -1).contains(sendRect),
                             "Input and send must be visible together in their ancestor viewport and window")
                try #require(!inputRect.intersects(sendRect), "Input and send must not overlap")
                let renderedDraft = input.accessibilityValue == draft || objects(window).contains {
                    let text = ($0 as? UITextView)?.text ?? ($0 as? UITextField)?.text
                    guard text == draft, let view = $0 as? UIView else { return false }
                    return inputRect.intersects(view.convert(view.bounds, to: window))
                }
                try #require(renderedDraft, "The actual public text input must contain the preserved draft")
                let toolbar = objects(window).filter {
                    let label = $0.accessibilityLabel ?? ""
                    return label == "画像を添付" || label == "思考の強さと権限を変更"
                        || label.hasPrefix("モデル、") || label.hasPrefix("プロジェクト、") || label.hasPrefix("思考の強さ、")
                }
                try #require(!toolbar.isEmpty, "Public composer toolbar controls must be observable")
                for control in toolbar {
                    let rect = frame(control)
                    try #require(finite(rect) && !rect.intersects(inputRect), "Toolbar must not overlap the actual text input")
                }
            }
            let errorParts = presentation.map { [$0.title, $0.cause, $0.nextStep, $0.technicalDetail ?? ""].filter { !$0.isEmpty } } ?? []
            let errorElements = try errorParts.map { text in
                try #require(all.first { $0.accessibilityLabel?.contains(text) == true }, "Full canonical catalog text must exist: \(text)")
            }
            var requiredElements = [input, send] + errorElements
            var usageElement: NSObject?
            let inputRect = frame(input)
            let placeholderReference = UIHostingController(rootView: Text("やりたいことを入力")
                .font(DSFont.inputBar(.textField, for: .accessibility5)).fixedSize(horizontal: false, vertical: true)
                .environment(\.dynamicTypeSize, .accessibility5).environment(\.locale, Locale(identifier: "ja_JP")))
            let placeholderNatural = placeholderReference.sizeThatFits(in: CGSize(width: inputRect.width, height: .greatestFiniteMagnitude))
            naturalMeasurements["inputActual"] = String(describing: inputRect)
            naturalMeasurements["placeholderNatural"] = String(describing: placeholderNatural)
            try #require(finite(inputRect) && placeholderNatural.height.isFinite && placeholderNatural.height > 0
                && inputRect.height >= placeholderNatural.height - 1,
                         "The actual empty input must retain the full AX5 placeholder natural height")
            if let usageViewModel {
                if usageViewModel.shouldShowRow {
                    let rowLabel = UsageRingPresentation.accessibilityLabel(agents: usageViewModel.presentationAgents,
                        isRefreshing: usageViewModel.isRefreshing, isStale: usageViewModel.isStale, asOf: usageViewModel.asOfDate)
                    let row = try #require(snapshotAccessibilityElement(in: window, identifier: "UsageRingRow.button")
                        ?? snapshotAccessibilityElement(in: window, label: rowLabel))
                    usageElement = row
                    requiredElements.append(row)
                    let rowRect = frame(row)
                    try #require(finite(inputRect) && finite(rowRect))
                    let rowReference = UIHostingController(rootView: UsageRingRow(viewModel: usageViewModel)
                        .environment(\.dynamicTypeSize, .accessibility5).environment(\.locale, Locale(identifier: "ja_JP")))
                    let rowNatural = rowReference.sizeThatFits(in: CGSize(width: rowRect.width, height: .greatestFiniteMagnitude))
                    naturalMeasurements["usageActual"] = String(describing: rowRect)
                    naturalMeasurements["usageNatural"] = String(describing: rowNatural)
                    try record("natural-reference")
                    try #require(rowNatural.height.isFinite && rowNatural.height > 0 && rowRect.height >= rowNatural.height - 1,
                                 "The actual Usage row must retain its same-VM AX5 natural height")
                    try #require(!rowRect.intersects(inputRect) && !rowRect.intersects(frame(send)), "Usage must not overlap input or send")
                } else {
                    try #require(snapshotAccessibilityElement(in: window, identifier: "UsageRingRow.button") == nil,
                                 "No accessible usage button may remain when no valid bucket is available")
                }
            }
            if usageViewModel != nil, presentation == nil {
                let root = try #require(window.rootViewController?.viewIfLoaded)
                let hostViewport = root.convert(root.safeAreaLayoutGuide.layoutFrame, to: window)
                let fits = finite(hostViewport) && requiredElements.allSatisfy {
                    let rect = frame($0)
                    return finite(rect) && hostViewport.insetBy(dx: -1, dy: -1).contains(rect)
                }
                if fits {
                    try verifyComposer(in: hostViewport)
                    naturalMeasurements["reachabilityMode"] = "static-fit-in-actual-host-viewport"
                    try record("usage-static-fit")
                    return
                }
            }
            let nativeInput = all.compactMap { $0 as? UIView }.first {
                ($0 as? UITextView)?.text == draft || ($0 as? UITextField)?.text == draft
            }
            let scroll = try #require(all.compactMap { $0 as? UIScrollView }.filter { scroll in
                guard scroll.window === window, scroll.isScrollEnabled, scroll.bounds.width >= window.bounds.width * 0.7,
                      scroll.bounds.height > 0, scroll.contentSize.width.isFinite, scroll.contentSize.height.isFinite else { return false }
                if usageViewModel != nil && nativeInput?.isDescendant(of: scroll) != true { return false }
                let content = CGRect(origin: .zero, size: scroll.contentSize).insetBy(dx: -1, dy: -1)
                return requiredElements.allSatisfy {
                    let rect = frame($0)
                    return finite(rect) && content.contains(scroll.convert(rect, from: window))
                }
            }.min { $0.contentSize.height < $1.contentSize.height }, "A real finite native scroll must contain the error and composer")
            if !errorElements.isEmpty {
                let errorRect = errorElements.map { scroll.convert(frame($0), from: window) }.reduce(CGRect.null) { $0.union($1) }
                let viewportHeight = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
                try #require(finite(errorRect) && viewportHeight.isFinite && viewportHeight > 0)
                scroll.scrollRectToVisible(CGRect(x: errorRect.minX, y: errorRect.minY,
                    width: errorRect.width, height: min(errorRect.height, viewportHeight)), animated: false)
                window.layoutIfNeeded()
                await Task.yield()
                let topViewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window).intersection(window.bounds)
                let errorStart = scroll.convert(CGPoint(x: errorRect.midX, y: errorRect.minY + 1), to: window)
                try record("error-top")
                try image("error-top")
                try #require(finite(topViewport) && topViewport.insetBy(dx: -1, dy: -1).contains(errorStart),
                             "The error start must actually reach the visible viewport after public scroll")
            }
            if let usageElement {
                scroll.scrollRectToVisible(scroll.convert(frame(usageElement), from: window), animated: false)
                window.layoutIfNeeded(); await Task.yield()
                let root = try #require(window.rootViewController?.viewIfLoaded)
                let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
                    .intersection(root.convert(root.safeAreaLayoutGuide.layoutFrame, to: window))
                try record("usage-reachable")
                try #require(finite(frame(usageElement)) && viewport.insetBy(dx: -1, dy: -1).contains(frame(usageElement)),
                             "The natural Usage row must be reachable in its actual host viewport")
            }
            @MainActor
            func liveBottom() -> CGFloat {
                max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            }
            let deadline = ContinuousClock.now + .seconds(5)
            repeat {
                window.layoutIfNeeded()
                try #require(liveBottom().isFinite && scroll.contentSize.height.isFinite)
                scroll.scrollRectToVisible(CGRect(x: 0, y: max(0, scroll.contentSize.height - 1), width: 1, height: 1), animated: false)
                await Task.yield()
                window.layoutIfNeeded()
                try #require(liveBottom().isFinite)
                if abs(scroll.contentOffset.y - liveBottom()) <= 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            } while ContinuousClock.now < deadline
            window.layoutIfNeeded()
            try record("bottom")
            try #require(abs(scroll.contentOffset.y - liveBottom()) <= 1, "Public scroll must reach the live content-derived bottom")
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            let root = try #require(window.rootViewController?.viewIfLoaded)
            var visible = viewport.intersection(root.convert(root.safeAreaLayoutGuide.layoutFrame, to: window))
            var ancestor = scroll.superview
            while let view = ancestor, view !== window {
                try #require(!view.isHidden && view.alpha > 0, "The composer scroll must have visible ancestors")
                if view.clipsToBounds { visible = visible.intersection(view.convert(view.bounds, to: window)) }
                ancestor = view.superview
            }
            try #require(finite(viewport))
            try verifyComposer(in: visible)
        } catch {
            try record("failure")
            try image("failure")
            throw error
        }
    }

    /// ListMany専用。実寸法の連続安定を待ち、固定sleepで展開途中を隠さない。
    private func waitForExpandedListGeometry(_ window: UIWindow, scenarioID: String, output: URL) async throws {
        let observer = SnapshotListGeometryObserver(window: window)
        observer.start()
        defer { observer.stop() }
        let deadline = ContinuousClock.now + .seconds(10)
        do {
            while !observer.isStable, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            try observer.writeTrace(to: output.appendingPathComponent("\(scenarioID)-list-geometry-cancelled.json"), result: "interrupted")
            throw error
        }
        try observer.writeTrace(to: output.appendingPathComponent("\(scenarioID)-list-geometry.json"), result: observer.isStable ? "stable" : "timeout")
        try #require(observer.isStable, "Expanded ListMany geometry did not remain stable for a disclosure-duration interval")
    }

    private func windowImage<Content: View>(
        _ content: Content,
        size: CGSize,
        safeArea: UIEdgeInsets,
        scale: CGFloat,
        dark: Bool,
        scenarioID: String,
        contentSizeCategory: UIContentSizeCategory? = nil,
        settleDelay: Duration = .milliseconds(20),
        waitUntilReady: (() async throws -> Void)? = nil,
        prepareWindow: ((UIWindow) async throws -> Void)? = nil
    ) async throws -> UIImage {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        defer {
            if let previousKeyWindow, !previousKeyWindow.isHidden {
                previousKeyWindow.makeKey()
            }
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if let contentSizeCategory {
            window.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        }
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.isHidden = false
        if prepareWindow != nil { window.makeKeyAndVisible() }
        var closed = false
        defer {
            if !closed {
                window.isHidden = true
                window.rootViewController = nil
            }
        }

        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        let originalInsets = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(
            top: safeArea.top - originalInsets.top,
            left: safeArea.left - originalInsets.left,
            bottom: safeArea.bottom - originalInsets.bottom,
            right: safeArea.right - originalInsets.right
        )
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        #expect(abs(host.view.safeAreaInsets.top - safeArea.top) < 0.5)
        #expect(abs(host.view.safeAreaInsets.bottom - safeArea.bottom) < 0.5)
        await Task.yield()
        try await Task.sleep(for: settleDelay)
        try await waitUntilReady?()
        try await prepareWindow?(window)
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let deadline = ContinuousClock.now + .seconds(10)
        var lastImage: UIImage?
        repeat {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            var drawn = false
            let image = renderer.image { _ in
                drawn = window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            let hasBody = hasBodyContent(image)
            lastImage = image
            if drawn && hasBody {
                window.isHidden = true
                try await Task.sleep(for: .milliseconds(100))
                window.rootViewController = nil
                closed = true
                try await Task.sleep(for: .milliseconds(100))
                return image
            }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        let debugDirectory = try outputDirectory(variables: ProcessInfo.processInfo.environment)
        try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        let osMajor = UIDevice.current.systemVersion.split(separator: ".").first ?? "unknown"
        let debugURL = debugDirectory.appendingPathComponent("body-failure-\(scenarioID)-\(Int(size.width))x\(Int(size.height))-ios\(osMajor).png")
        let debugPNG = try #require(lastImage?.pngData())
        try debugPNG.write(to: debugURL, options: .atomic)
        print("snapshot body failure image: \(debugURL.path)")
        throw SnapshotError.bodyDidNotRender
    }

    private func waitForExternalUsageActivation(window: UIWindow, output: URL, sceneName: String, requiresPopover: Bool = true) async throws {
        let readyURL = output.appendingPathComponent("\(sceneName)-external-ready.json")
        func writePhase(_ phase: String) throws {
            let payload: [String: Any] = [
                "scene": sceneName, "phase": phase,
                "pid": ProcessInfo.processInfo.processIdentifier,
                "udid": ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown",
                "window": [window.bounds.origin.x, window.bounds.origin.y, window.bounds.width, window.bounds.height],
                "screen": [window.screen.bounds.origin.x, window.screen.bounds.origin.y, window.screen.bounds.width, window.screen.bounds.height],
                "sceneActivation": window.windowScene?.activationState.rawValue ?? -1,
                "visibleWindows": window.windowScene?.windows.filter { !$0.isHidden }.map {
                    "\(type(of: $0)) bounds=\($0.bounds) level=\($0.windowLevel.rawValue) key=\($0.isKeyWindow) root=\(String(describing: $0.rootViewController)) presented=\(String(describing: $0.rootViewController?.presentedViewController))"
                } ?? [],
            ]
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                .write(to: readyURL, options: .atomic)
            FileHandle.standardError.write(Data("external usage \(phase): \(readyURL.path)\n".utf8))
        }
        try writePhase("awaitingTap")
        do {
            func isPresented() -> Bool {
                requiresPopover ? snapshotHasPresentedPopover(window.rootViewController) : snapshotHasPresentedController(window.rootViewController)
            }
            let deadline = ContinuousClock.now + .seconds(60)
            while !isPresented(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            try #require(isPresented(), "External tap did not present the real interface: \(sceneName)")
            try writePhase("presented")
        } catch {
            try writePhase("failed")
            throw error
        }
    }

    private func waitForExternalPopoverAXEvidence(window: UIWindow, output: URL, sceneName: String) async throws -> Set<String> {
        let variables = ProcessInfo.processInfo.environment
        let windowTitle = try #require(variables["PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE"] ?? variables["SIMULATOR_DEVICE_NAME"])
        let nonce = UUID().uuidString
        let proofURL = output.appendingPathComponent("\(sceneName)-\(nonce)-external-ax.json")
        let readyURL = output.appendingPathComponent("\(sceneName)-external-ready.json")
        var request = SnapshotExternalAXRequest(
            nonce: nonce, scene: sceneName, phase: "awaitingAXProof",
            pid: ProcessInfo.processInfo.processIdentifier,
            udid: try #require(variables["SIMULATOR_UDID"]), windowTitle: windowTitle,
            requestedAt: Date().timeIntervalSince1970,
            nativeContentSizeCategory: window.traitCollection.preferredContentSizeCategory.rawValue,
            proofFile: proofURL.path
        )
        func writeRequest() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(request).write(to: readyURL, options: .atomic)
            print("external usage \(request.phase): \(readyURL.path)")
        }
        try writeRequest()
        do {
            let deadline = ContinuousClock.now + .seconds(60)
            while !FileManager.default.fileExists(atPath: proofURL.path), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            try #require(FileManager.default.fileExists(atPath: proofURL.path), "Fresh external popover AX evidence was not provided")
            let evidence = try JSONDecoder().decode(SnapshotExternalAXEvidence.self, from: Data(contentsOf: proofURL))
            let labels = try evidence.validatedLabels(for: request, now: Date().timeIntervalSince1970)
            try #require(snapshotHasPresentedPopover(window.rootViewController), "Popover closed before AX evidence was validated")
            request.phase = "validatedAXProof"
            try writeRequest()
            return labels
        } catch {
            request.phase = "failedAXProof"
            try writeRequest()
            throw error
        }
    }

    private func waitForSnapshotAccessibilityElement(in window: UIWindow, identifier: String) async throws -> NSObject {
        let deadline = ContinuousClock.now + .seconds(3)
        repeat {
            if let element = snapshotAccessibilityElement(in: window, identifier: identifier) { return element }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        snapshotAccessibilityDiagnostics(window)
        return try #require(snapshotAccessibilityElement(in: window, identifier: identifier), "AX element did not appear: \(identifier)")
    }

    private func snapshotAccessibilityDiagnostics(_ window: UIWindow) {
        var lines = ["AX window scene=\(String(describing: window.windowScene)) key=\(window.isKeyWindow) hidden=\(window.isHidden) root=\(String(describing: window.rootViewController)) bounds=\(window.bounds) screenBounds=\(window.screen.bounds) sceneBounds=\(String(describing: window.windowScene?.coordinateSpace.bounds)) safeArea=\(window.safeAreaInsets)"]
        var visited = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 20, lines.count < 160, visited.insert(ObjectIdentifier(object)).inserted else { return }
            let identifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? "nil"
            let children = object.accessibilityElements ?? []
            let count = object.accessibilityElementCount()
            lines.append("AX depth=\(depth) type=\(type(of: object)) id=\(identifier) label=\(object.accessibilityLabel ?? "nil") element=\(object.isAccessibilityElement) array=\(children.count) count=\(count)")
            for child in children {
                if let child = child as? NSObject { walk(child, depth: depth + 1) }
            }
            if count != NSNotFound, count > 0, count < 200 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { walk(child, depth: depth + 1) }
                }
            }
            if let view = object as? UIView {
                lines.append("UIView frame=\(view.frame) windowConnected=\(view.window?.windowScene != nil) subviews=\(view.subviews.count)")
                for child in view.subviews { walk(child, depth: depth + 1) }
            }
        }
        walk(window, depth: 0)
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    private func snapshotHasPresentedPopover(_ controller: UIViewController?) -> Bool {
        snapshotPresentedPopover(controller) != nil
    }

    private func snapshotPresentedPopover(_ controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController {
            if presented.presentingViewController != nil, presented.popoverPresentationController != nil { return presented }
            if let popover = snapshotPresentedPopover(presented) { return popover }
        }
        return controller.children.lazy.compactMap { snapshotPresentedPopover($0) }.first
    }

    private func snapshotHasPresentedController(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        if controller.presentedViewController?.presentingViewController != nil { return true }
        return controller.children.contains { snapshotHasPresentedController($0) }
    }

    // UIViewのsubviewsは辿らず、公開されたAXコンテナの子だけを検査する。
    private func snapshotExposedAccessibilityElement(in root: NSObject, label: String) -> NSObject? {
        var visited: Set<ObjectIdentifier> = []
        func search(_ object: NSObject, fromAccessibilityContainer: Bool) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            let isExposedElement = object.isAccessibilityElement
                || (fromAccessibilityContainer && !(object is UIView))
            if isExposedElement, object.accessibilityLabel == label { return object }
            for child in object.accessibilityElements ?? [] {
                if let child = child as? NSObject,
                   let found = search(child, fromAccessibilityContainer: true) { return found }
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject,
                       let found = search(child, fromAccessibilityContainer: true) { return found }
                }
            }
            return nil
        }
        return search(root, fromAccessibilityContainer: false)
    }

    private func snapshotAccessibilityElement(
        in window: UIWindow, identifier: String? = nil, label: String? = nil
    ) -> NSObject? {
        var visited: Set<ObjectIdentifier> = []
        func search(_ object: NSObject) -> NSObject? {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            if let identifier,
               (object as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return object }
            if let label, object.accessibilityLabel == label { return object }
            if let children = object.accessibilityElements {
                for child in children {
                    if let child = child as? NSObject, let found = search(child) { return found }
                }
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound && count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject,
                       let found = search(child) { return found }
                }
            }
            if let view = object as? UIView {
                for child in view.subviews {
                    if let found = search(child) { return found }
                }
            }
            return nil
        }
        return search(window)
    }

    // 中央にある本文と、上側に集まる一覧の本文を検査する。上下のバーだけでは成功しない。
    private func hasBodyContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return false }
        let bodyRegions = [
            height / 4..<height * 3 / 4,
            height / 12..<height * 7 / 12,
            height * 3 / 4..<height * 11 / 12,
        ]
        for yRange in bodyRegions {
            var colors: [Int: Int] = [:]
            var rows = Set<Int>()
            var samples: [(Int, Int)] = []
            for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: 2) {
                for x in stride(from: width / 12, to: width * 11 / 12, by: 2) {
                    let i = (y * width + x) * 4
                    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                    let yellow = r > 160 && g > 120 && b < 100
                    let key = yellow ? -1 : (r / 16) * 256 + (g / 16) * 16 + b / 16
                    colors[key, default: 0] += 1
                    samples.append((key, y))
                }
            }
            guard let background = colors.max(by: { $0.value < $1.value })?.key else { continue }
            guard Double(colors[-1, default: 0]) / Double(max(1, samples.count)) < 0.01 else { continue }
            var foreground = 0
            for (key, y) in samples where key != background && key != -1 {
                foreground += 1
                rows.insert(y / 16)
            }
            if Double(foreground) / Double(max(1, samples.count)) > 0.01 && rows.count >= 4 {
                return true
            }
        }
        return false
    }


    private func snapshotDimensionOverflowData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 8001, height: 1)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func snapshotAttachmentData(color: UIColor, label: String? = nil) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            (label == nil ? color : UIColor.white).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            if let label {
                UIColor.separator.setStroke()
                UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 62, height: 62), cornerRadius: 8).stroke()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
                    .foregroundColor: label == "502" ? UIColor.systemRed : UIColor.secondaryLabel,
                ]
                let textSize = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(
                    at: CGPoint(x: (64 - textSize.width) / 2, y: (64 - textSize.height) / 2),
                    withAttributes: attributes
                )
                if label == "LOG" {
                    UIColor.systemGray3.setFill()
                    for y in [44, 49, 54] { context.fill(CGRect(x: 12, y: y, width: 40, height: 2)) }
                }
            }
        }
    }

}

private enum SnapshotError: Error { case bodyDidNotRender }

@MainActor
private struct PairConnectionSettingsSnapshotView: View {
    @State private var faceIDEnabled = true
    let connectionViewModel: ConnectionSettingsViewModel
    let onQRScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                Text("設定")
                    .font(DSFont.largeTitle)
                    .foregroundStyle(IOSColor.text.primary)

                ConnectionSettingsSection(viewModel: connectionViewModel, onQRScan: onQRScan)

                Text("接続先は、Mac の Phlox が表示する QR から設定します。")
                    .font(DSFont.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DSSpacing.m)

                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    DSSectionLabel("セキュリティ")
                    HStack {
                        Text("Face ID でロック")
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textPrimary)
                        Spacer(minLength: DSSpacing.s)
                        Toggle("Face ID でロック", isOn: $faceIDEnabled)
                            .labelsHidden()
                            .tint(IOSColor.toggleOn)
                    }
                    .padding(.horizontal, DSSpacing.m)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))

                    Text("起動時とバックグラウンドからの復帰時に認証します。")
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, DSSpacing.m)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, DSSpacing.m)
        }
        .background(IOSColor.bg.base)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SnapshotExternalAXRequest: Codable {
    let nonce: String
    let scene: String
    var phase: String
    let pid: Int32
    let udid: String
    let windowTitle: String
    let requestedAt: TimeInterval
    let nativeContentSizeCategory: String
    let proofFile: String
}

private enum SnapshotExternalAXValidationError: Error {
    case wrongIdentity
    case staleEvidence
    case wrongWindow
    case missingPopoverContent
    case wrongLayout
}

private struct SnapshotExternalAXEvidence: Codable {
    let nonce: String
    let scene: String
    let phase: String
    let pid: Int32
    let udid: String
    let windowTitle: String
    let capturedAt: TimeInterval
    let rawAXTree: String

    func validatedLabels(for request: SnapshotExternalAXRequest, now: TimeInterval) throws -> Set<String> {
        guard nonce == request.nonce, scene == request.scene, phase == "presentedAX",
              pid == request.pid, udid == request.udid else {
            throw SnapshotExternalAXValidationError.wrongIdentity
        }
        guard capturedAt >= request.requestedAt, capturedAt <= now + 5,
              now - capturedAt <= 120 else {
            throw SnapshotExternalAXValidationError.staleEvidence
        }
        guard !windowTitle.isEmpty, windowTitle == request.windowTitle,
              rawAXTree.contains("Window: \"\(windowTitle)\", App: Simulator.") else {
            throw SnapshotExternalAXValidationError.wrongWindow
        }
        var labels: Set<String> = []
        for line in rawAXTree.split(separator: "\n") {
            let element = line.trimmingCharacters(in: .whitespaces)
            guard element.first?.isNumber == true else { continue }
            for field in ["Description: ", "Title: ", "Value: "] {
                guard let range = element.range(of: field) else { continue }
                let value = element[range.upperBound...].components(separatedBy: ", ")[0]
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
                if !value.isEmpty { labels.insert(value) }
            }
        }
        let services = Set([AgentKind.claudeCode, .codex, .cursor].map(\.displayName))
        guard services.isSubset(of: labels) else { throw SnapshotExternalAXValidationError.missingPopoverContent }
        return labels
    }

    static func validateUsageLayout(labels: Set<String>, isAccessibilitySize: Bool) throws {
        let headers = Set(UsageRingPresentation.popoverColumnHeaders)
        guard isAccessibilitySize ? labels.isDisjoint(with: headers) : headers.isSubset(of: labels) else {
            throw SnapshotExternalAXValidationError.wrongLayout
        }
    }
}

private struct SessionDetailSnapshotCase {
    var name: String
    let session: Session
    let messages: SessionDetailSnapshotMessages
    var approvals: [Approval] = []
    var usage: TurnUsage?
    var recovery: SessionDetailRecovery?
    var isNewSession = false
    var attachmentPreviews: [String: [Data]] = [:]
    var expandedMessageIDs: Set<String> = []
    var statusAge: TimeInterval?
    var width: CGFloat = 428
    var height: CGFloat = 926
    var isDark = false
    var isAccessibilitySize = false
    var startsAtTop = false
    var replyState: SessionDetailViewModel.ReplySnapshotState?
    var inputText = ""
    var modelName: String?
    var permission = "acceptEdits"
    var inputAttachments: [Data] = []
    var showsModelPicker = false
    var showsRename = false
    var sendFailure: PhloxError?
}

private enum SessionDetailSnapshotMessages: Sendable {
    case success([ChatMessage])
    case failure(PhloxError)
    case suspended
}

private struct SessionDetailSnapshotHost: View {
    @State private var path: [Route] = []

    let list: SessionListViewModel
    let navigationState: SessionNavigationState
    let snapshot: SessionDetailSnapshotCase
    let session: Session
    let api: SessionDetailSnapshotAPI
    var preparedModel: SessionDetailViewModel? = nil

    var body: some View {
        AppShellView(
            selection: .constant(.sessions), navigationState: navigationState,
            reachability: .online, lastFetchedAt: list.lastFetchedAt, host: "100.64.0.1:8765",
            hidesTabBar: true, hidesAccessory: true,
            onOpenSession: { _ in }, onShowSessionList: {}, onReconnect: {}
        ) {
            NavigationStack(path: $path) {
                SessionListView(
                    viewModel: list, reachability: .online, endpoint: "100.64.0.1:8765",
                    onSelectDetail: { _ in }, onAddSession: { _ in }
                )
                .navigationStackHomeBackButton()
                .task {
                    await Task.yield()
                    guard path.isEmpty else { return }
                    path = [.sessionDetail(id: session.id)]
                }
                .navigationDestination(for: Route.self) { route in
                    if case .sessionDetail = route {
                        if let preparedModel {
                            SessionDetailView(viewModel: preparedModel, onDelete: {})
                                .toolbar(.hidden, for: .tabBar)
                        } else {
                            SessionDetailFixtureDestination(session: session, api: api, snapshot: snapshot)
                                .toolbar(.hidden, for: .tabBar)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
            .dsCampNavigationChrome()
        } settings: {
            NavigationStack { EmptyView() }
                .dsCampNavigationChrome()
        }
    }
}

// 撮影時の入力値は、本番APIや本番Destinationに撮影専用の引数を足さずに設定する。
private struct SessionDetailFixtureDestination: View {
    @State private var viewModel: SessionDetailViewModel
    let snapshot: SessionDetailSnapshotCase
    let readiness: SessionDetailSnapshotReadiness?

    init(session: Session, api: SessionDetailSnapshotAPI, snapshot: SessionDetailSnapshotCase) {
        self.snapshot = snapshot
        readiness = api.readiness
        let model = SessionDetailViewModel(
            session: session, api: api, recovery: snapshot.recovery,
            isNewSession: snapshot.isNewSession,
            initialAttachmentPreviews: snapshot.attachmentPreviews,
            initialExpandedMessageIDs: snapshot.expandedMessageIDs
        )
        if snapshot.recovery == nil {
            model.addAttachments(snapshot.inputAttachments.map { SendAttachment(mediaType: "image/png", data: $0) })
            model.inputText = snapshot.inputText
            model.inputCursorUTF16 = snapshot.inputText.utf16.count
        }
        if let state = snapshot.replyState { model.configureReplySnapshot(state) }
        _viewModel = State(initialValue: model)
    }

    var body: some View {
        SessionDetailView(viewModel: viewModel, scrollToBottomOnAppear: !snapshot.startsAtTop, onDelete: {})
            .task(id: viewModel.currentReplyApproval?.armKey) {
                if viewModel.currentReplyApproval != nil {
                    await readiness?.markApprovalVisible()
                }
            }
            .task {
                if snapshot.showsModelPicker {
                    await viewModel.loadModelSettings()
                    viewModel.beginModelSelection()
                }
                if snapshot.showsRename { viewModel.beginRename() }
            }
    }
}

/// Shares the existing model-capable snapshot API without exposing its private implementation types.
func makeAdditionalModelPresentationSnapshotAPI(session: Session) -> any PhloxAPI & SessionModelSelecting {
    SessionDetailSnapshotAPI(
        session: session, messages: .success([]), approvals: [], turnUsage: nil, readiness: nil
    )
}

private struct SessionDetailSnapshotAPI: PhloxAPI, SessionModelSelecting {
    let session: Session
    let messages: SessionDetailSnapshotMessages
    let approvals: [Approval]
    let turnUsage: TurnUsage?
    let readiness: SessionDetailSnapshotReadiness?
    var modelName: String?
    var permission = "acceptEdits"
    var usageStyle: UITestUsageFixtures.Style = .normal
    var sendGate: SnapshotResponseGate?
    var failsSettings = false
    var usageSource: SnapshotUsageSource?
    var sendFailure: PhloxError?

    private var model: SessionModelOption {
        if let modelName { return SessionModelOption(id: "haiku-5.5", displayName: modelName) }
        if session.agent == .codex {
            return SessionModelOption(id: "gpt-6.1-sol", displayName: "gpt-6.1-sol")
        }
        return SessionModelOption(id: "sonnet-5", displayName: "Sonnet 5")
    }

    private var models: [SessionModelOption] {
        session.agent == .codex ? [model] : [
            SessionModelOption(id: "sonnet-5", displayName: "Sonnet 5"),
            SessionModelOption(id: "opus-1m", displayName: "Opus (1M context)"),
            SessionModelOption(id: "haiku-5.5", displayName: "Haiku 5.5"),
        ]
    }

    func listSessions() async throws -> [Session] { [session] }
    func usage(sessionID: String) async throws -> TurnUsage? { turnUsage }
    func spawn(_ request: SpawnRequest) async throws -> Session { session }
    func agentSettings(kind: AgentKind) async throws -> AgentSettings? { nil }
    func projects() async throws -> [ProjectSummary]? { [] }
    func cliUsage() async throws -> [CLIUsage] {
        if let usageSource { return try await usageSource.fetch() }
        return UITestUsageFixtures.values(for: usageStyle)
    }
    func agentModels(kind: AgentKind) async throws -> AgentModels { AgentModels(models: models, defaultModel: session.agent == .codex ? model.id : "sonnet-5") }
    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        SessionModelSettings(
            selectedModel: model.id,
            availableModels: models,
            selectedEffort: modelName == "Haiku 5.5" ? nil : (session.agent == .codex ? "medium" : "high"),
            availableEfforts: modelName == "Haiku 5.5" ? [] : session.agent == .codex
                ? [
                    AgentSettingOption(value: "low", displayName: "低"),
                    AgentSettingOption(value: "medium", displayName: "中"),
                    AgentSettingOption(value: "high", displayName: "高"),
                ]
                : [AgentSettingOption(value: "high", displayName: "高")],
            selectedPermission: session.agent == .codex ? nil : permission,
            availablePermissions: session.agent == .codex
                ? [AgentSettingOption(value: nil, displayName: "Default")]
                : [AgentSettingOption(value: "manual", displayName: "Manual"), AgentSettingOption(value: "acceptEdits", displayName: "Accept Edits"), AgentSettingOption(value: "bypassPermissions", displayName: "Bypass Permissions")],
            planMode: false,
            planModeAvailable: true
        )
    }
    func setModel(sessionID: String, model: String) async throws {}
    func updateSessionSettings(sessionID: String, update: SessionSettingsUpdate) async throws {
        if failsSettings { throw PhloxError.server(status: 500, message: "Snapshot permission update failed") }
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult {
        try await sendGate?.wait()
        if let sendFailure { throw sendFailure }
        return SendResult(accepted: true)
    }
    func messages(sessionID: String) async throws -> [ChatMessage] {
        switch messages {
        case .success(let messages):
            await readiness?.markMessagesLoaded()
            return messages
        case .failure(let error):
            await readiness?.markMessagesLoaded()
            throw error
        case .suspended:
            try await Task.sleep(for: .seconds(60))
            await readiness?.markMessagesLoaded()
            return []
        }
    }
    func remove(sessionID: String) async throws {}
    func rename(sessionID: String, name: String) async throws {}
    func approvals() async throws -> [Approval] {
        await readiness?.markApprovalsLoaded()
        return approvals
    }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}

// 未完了応答を撮影側で解放する。キャンセルもsleepを中断し、継続を残さない。
private actor SnapshotResponseGate {
    private var entered = false
    private var released = false

    func wait() async throws {
        entered = true
        while !released { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
    }

    func waitUntilEntered() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !entered {
            guard ContinuousClock.now < deadline else { throw SnapshotError.bodyDidNotRender }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func release() { released = true }
}

private actor SnapshotUsageSource {
    let style: UITestUsageFixtures.Style
    private var fails = false
    private var gate: SnapshotResponseGate?

    init(style: UITestUsageFixtures.Style) { self.style = style }

    func configure(fails: Bool, gate: SnapshotResponseGate?) {
        self.fails = fails
        self.gate = gate
    }

    func fetch() async throws -> [CLIUsage] {
        if fails { throw PhloxError.server(status: 503, message: "Snapshot usage unavailable") }
        try await gate?.wait()
        return UITestUsageFixtures.values(for: style)
    }
}

private actor SessionDetailSnapshotReadiness {
    private var messagesLoaded = false
    private var approvalsLoaded = false
    private var approvalVisible = false
    private var messageWaiter: CheckedContinuation<Void, Never>?
    private var approvalWaiter: CheckedContinuation<Void, Never>?

    func markApprovalVisible() { approvalVisible = true }

    func waitForApprovalVisible() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !approvalVisible, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(approvalVisible, "Expected real approval card did not become ready")
    }

    func markMessagesLoaded() {
        messagesLoaded = true
        messageWaiter?.resume()
        messageWaiter = nil
    }

    func markApprovalsLoaded() {
        approvalsLoaded = true
        approvalWaiter?.resume()
        approvalWaiter = nil
    }

    func waitForMessages() async {
        guard !messagesLoaded else { return }
        await withCheckedContinuation { messageWaiter = $0 }
    }

    func waitForApprovals() async {
        guard !approvalsLoaded else { return }
        await withCheckedContinuation { approvalWaiter = $0 }
    }
}

private struct NewChatSnapshotHost: View {
    @State private var path: [Route] = []
    let viewModel: NewChatViewModel
    let usageViewModel: UsageViewModel
    let greeting: String
    let dark: Bool
    let ax5: Bool

    var body: some View {
        NavigationStack(path: $path) {
            Text("セッション一覧")
                .navigationTitle("セッション一覧")
                .navigationStackHomeBackButton()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .newChat:
                        NewChatView(
                            viewModel: viewModel,
                            fixedGreeting: greeting,
                            focusOnAppear: false,
                            onCreated: { _, _ in }
                        )
                        .environment(\.usageViewModel, usageViewModel)
                    default:
                        Color.clear
                    }
                }
        }
        .task {
            await Task.yield()
            path = [.newChat(SessionComposeDraft(project: ""))]
        }
        .dsCampNavigationChrome()
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.dynamicTypeSize, ax5 ? .accessibility5 : .large)
        .environment(\.locale, Locale(identifier: "ja_JP"))
    }
}

private struct NewChatSnapshotAPI: PhloxAPI {
    var spawnFailure: PhloxError? = nil
    func listSessions() async throws -> [Session] { [] }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        if let spawnFailure { throw spawnFailure }
        return Session(
            id: "snapshot-new-session",
            name: "snapshot-new-session",
            agent: request.agent,
            status: .starting,
            subtitle: "",
            projectId: request.projectID,
            projectName: request.workspace,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    func agentModels(kind: AgentKind) async throws -> AgentModels {
        switch kind {
        case .claudeCode:
            return AgentModels(models: [
                SessionModelOption(id: "opus", displayName: "Opus (1M context)"),
                SessionModelOption(id: "sonnet", displayName: "Sonnet 5"),
                SessionModelOption(id: "haiku-5.5", displayName: "Haiku 5.5"),
            ], defaultModel: "sonnet")
        case .codex:
            return AgentModels(models: [
                SessionModelOption(id: "gpt-6.1-sol", displayName: "gpt-6.1-sol"),
                SessionModelOption(id: "gpt-6.1-codex", displayName: "gpt-6.1-codex"),
                SessionModelOption(id: "gpt-6.1-mini", displayName: "gpt-6.1-mini"),
            ], defaultModel: "gpt-6.1-sol")
        case .cursor:
            return AgentModels(models: [
                SessionModelOption(id: "auto", displayName: "Auto"),
                SessionModelOption(id: "composer-1", displayName: "composer-1"),
                SessionModelOption(id: "sonnet-5-thinking", displayName: "sonnet-5-thinking"),
            ], defaultModel: "auto")
        }
    }

    func agentSettings(kind: AgentKind) async throws -> AgentSettings? {
        switch kind {
        case .claudeCode:
            AgentSettings(
                availableEfforts: [
                    "opus": [AgentSettingOption(value: "low", displayName: "低"), AgentSettingOption(value: "high", displayName: "高")],
                    "sonnet": [AgentSettingOption(value: "low", displayName: "低"), AgentSettingOption(value: "high", displayName: "高")],
                ],
                availablePermissions: [
                    AgentSettingOption(value: "auto", displayName: "Auto"),
                    AgentSettingOption(value: "manual", displayName: "Manual"),
                    AgentSettingOption(value: "bypassPermissions", displayName: "Bypass Permissions"),
                ],
                planModeAvailable: true
            )
        case .codex:
            AgentSettings(
                availableEfforts: ["gpt-6.1-sol": [AgentSettingOption(value: "medium", displayName: "中")]],
                availablePermissions: [
                    AgentSettingOption(value: ":read-only", displayName: "Read Only"),
                    AgentSettingOption(value: ":workspace", displayName: "Workspace"),
                    AgentSettingOption(value: ":danger-full-access", displayName: "Full Access"),
                ],
                planModeAvailable: true
            )
        case .cursor:
            AgentSettings(
                availableEfforts: ["composer-1": [AgentSettingOption(value: "medium", displayName: "中")]],
                availablePermissions: [
                    AgentSettingOption(value: nil, displayName: "既定"),
                    AgentSettingOption(value: "ask", displayName: "Ask"),
                ],
                planModeAvailable: true
            )
        }
    }

    func projects() async throws -> [ProjectSummary]? {
        [
            ProjectSummary(id: "project-phlox", name: "Phlox"),
            ProjectSummary(id: "project-simple-budget", name: "SimpleBudget"),
            ProjectSummary(id: "project-landing-page", name: "landing-page"),
            ProjectSummary(id: "project-dotfiles", name: "dotfiles"),
        ]
    }

    func cliUsage() async throws -> [CLIUsage] {
        let date = Date(timeIntervalSince1970: 1_792_300_000)
        func bucket(_ id: String, _ label: String, _ used: Double) -> UsageBucket {
            UsageBucket(id: id, label: label, usedPercent: used, resetsAt: date.addingTimeInterval(3600))
        }
        return [
            CLIUsage(kind: .claudeCode, state: .ok, buckets: [bucket("5h", "5時間", 48), bucket("weekly", "週次", 62)], updatedAt: date, dataAsOf: date),
            CLIUsage(kind: .codex, state: .ok, buckets: [bucket("5h", "5時間", 32), bucket("weekly", "週次", 42)], updatedAt: date, dataAsOf: date),
            CLIUsage(kind: .cursor, state: .ok, buckets: [bucket("auto", "Auto", 20), bucket("api", "API", 50)], updatedAt: date, dataAsOf: date),
        ]
    }

    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}

private struct InputBarSnapshotScenario {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let dark: Bool
    let isAccessibilitySize: Bool
    let text: String
    let isRunning: Bool
    let isSending: Bool
    let modelName: String
    let permission: String
    let showsEffort: Bool
    let attachmentCount: Int
    let attachmentError: String?
    let settingsError: String?
    let usageStyle: UITestUsageFixtures.Style
    let usageState: UsageViewModel.State
    let usageLastSuccessfulAt: Date?
    let showsUsagePopover: Bool
    let showsSessionDetailChrome: Bool

    init(
        name: String,
        width: CGFloat = 428,
        height: CGFloat = 926,
        dark: Bool = false,
        isAccessibilitySize: Bool = false,
        text: String = "",
        isRunning: Bool = false,
        isSending: Bool = false,
        modelName: String = "Sonnet 5",
        permission: String = "acceptEdits",
        showsEffort: Bool = true,
        attachmentCount: Int = 0,
        attachmentError: String? = nil,
        settingsError: String? = nil,
        usageStyle: UITestUsageFixtures.Style = .normal,
        usageState: UsageViewModel.State = .loaded,
        usageLastSuccessfulAt: Date? = UITestUsageFixtures.asOfDate,
        showsUsagePopover: Bool = false,
        showsSessionDetailChrome: Bool = true
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.dark = dark
        self.isAccessibilitySize = isAccessibilitySize
        self.text = text
        self.isRunning = isRunning
        self.isSending = isSending
        self.modelName = modelName
        self.permission = permission
        self.showsEffort = showsEffort
        self.attachmentCount = attachmentCount
        self.attachmentError = attachmentError
        self.settingsError = settingsError
        self.usageStyle = usageStyle
        self.usageState = usageState
        self.usageLastSuccessfulAt = usageLastSuccessfulAt
        self.showsUsagePopover = showsUsagePopover
        self.showsSessionDetailChrome = showsSessionDetailChrome
    }
}


private struct ComponentSnapshotView: View {
    private let statuses: [SessionStatus] = [
        .starting, .running, .awaitingApproval(prompt: ""), .awaitingUserQuestion,
        .error(message: ""), .completed(exitCode: 0),
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                Text("Agent")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                HStack(spacing: DSSpacing.l) {
                    DSAgentBrandIcon(kind: .claudeCode, size: 40)
                    DSAgentBrandIcon(kind: .codex, size: 40)
                    DSAgentBrandIcon(kind: .cursor, size: 40)
                }

                Text("状態")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    ForEach(statuses.indices, id: \.self) { index in
                        let presentation = IOSStatusVocabulary.presentation(
                            for: statuses[index], locale: Locale(identifier: "ja_JP")
                        )
                        if let label = presentation.label, let color = presentation.color {
                            Text(label)
                                .font(DSFont.body.weight(fontWeight(presentation.weight)))
                                .foregroundStyle(color)
                        }
                    }
                }

                Text("ガラス部品")
                    .font(DSFont.footnote.weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
                VStack(spacing: DSSpacing.s) {
                    glassExample("対応待ちバー") {
                        HStack {
                            Text("承認を待っています")
                            Spacer()
                            Image(systemName: "clock")
                        }
                        .padding(DSSpacing.m)
                        .glassSurface(.waitingBar)
                    }
                    glassExample("入力欄") {
                        HStack {
                            Text("返信を入力…")
                                .foregroundStyle(IOSColor.text.tertiary)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(IOSColor.accent)
                        }
                        .padding(DSSpacing.m)
                        .glassSurface(.inputField)
                    }
                    glassExample("承認・質問カード") {
                        Text("ファイルの変更を許可しますか？")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DSSpacing.m)
                            .glassSurface(.card)
                    }
                    glassExample("丸いボタン") {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                            .glassSurface(.roundButton)
                    }
                }
            }
            .padding(DSSpacing.l)
        }
        .background(IOSColor.bg.base.ignoresSafeArea())
    }

    private func glassExample<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSFont.caption)
                .foregroundStyle(IOSColor.text.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fontWeight(_ weight: IOSStatusWeight?) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case nil: .regular
        }
    }
}

/// 公開focusと実OSkeyboard通知の診断。通知やSwiftUI Stateを合成しない。
@MainActor
private final class SnapshotRealKeyboardProbe: NSObject {
    private weak var responder: UIView?
    private var notifications: [[String: Any]] = []
    private var lastScreenFrame: CGRect?
    private(set) var didShowLocalKeyboard = false
    private(set) var localKeyboardHideObservedAfterShow = false

    func start(responder: UIView) {
        self.responder = responder
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(receive(_:)), name: name, object: nil)
        }
    }
    func stop() {
        responder?.resignFirstResponder()
        NotificationCenter.default.removeObserver(self)
    }
    @objc private func receive(_ note: Notification) {
        let local = (note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool) == true
        let rect = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        if let rect { lastScreenFrame = rect }
        if note.name == UIResponder.keyboardDidShowNotification && local { didShowLocalKeyboard = true }
        if local && didShowLocalKeyboard && [UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification].contains(note.name) {
            localKeyboardHideObservedAfterShow = true
        }
        notifications.append(["name": note.name.rawValue, "local": local, "capturedAt": Date().timeIntervalSince1970,
                              "firstResponder": responder?.isFirstResponder ?? false, "screenFrame": String(describing: rect)])
    }
    func guideFrame(window: UIWindow) -> CGRect {
        guard let root = window.rootViewController?.viewIfLoaded else { return .null }
        return root.convert(root.keyboardLayoutGuide.layoutFrame, to: window)
    }
    func state(window: UIWindow) -> [String: Any] {
        ["screenBounds": String(describing: window.screen.bounds), "nativeScreenBounds": String(describing: window.screen.nativeBounds),
         "ownWindowBounds": String(describing: window.bounds), "syntheticWindow": true,
         "windowSafeAreaInsets": String(describing: window.safeAreaInsets),
         "hostSafeAreaInsets": String(describing: window.rootViewController?.viewIfLoaded?.safeAreaInsets),
         "hostSafeAreaLayoutFrame": String(describing: window.rootViewController?.viewIfLoaded?.safeAreaLayoutGuide.layoutFrame),
         "syntheticViewport": window.bounds.size != window.screen.bounds.size,
         "traitCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
         "keyboardGuideFrameInWindow": String(describing: guideFrame(window: window)),
         "keyboardFrameInScreen": String(describing: lastScreenFrame),
         "keyboardFrameInWindow": String(describing: lastScreenFrame.map { window.convert($0, from: window.screen.coordinateSpace) }),
         "didShowLocalKeyboard": didShowLocalKeyboard, "localKeyboardHideObservedAfterShow": localKeyboardHideObservedAfterShow,
         "firstResponder": responder?.isFirstResponder ?? false,
         "notifications": notifications]
    }
}

/// 実focus後の製品scrollを読取るだけで、delegate/offset/gestureを変更しない。
@MainActor
private final class SnapshotKeyboardFocusGeometryObserver: NSObject {
    private let window: UIWindow
    private let scroll: UIScrollView
    private let probe: SnapshotRealKeyboardProbe
    private weak var responder: UIView?
    private var link: CADisplayLink?
    private var previous: [CGFloat]?
    private var stableFrames = 0
    private var trace: [[String: Any]] = []
    private(set) var isStable = false
    init(window: UIWindow, scroll: UIScrollView, probe: SnapshotRealKeyboardProbe, responder: UIView) {
        self.window = window; self.scroll = scroll; self.probe = probe; self.responder = responder
    }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    var diagnostics: [String: Any] {
        ["scrollIdentity": String(describing: ObjectIdentifier(scroll)), "scrollClass": String(reflecting: type(of: scroll)),
         "stable": isStable, "requiredStableFrames": 3, "geometryTolerance": 0.5, "samples": trace]
    }
    @objc private func sample(_ link: CADisplayLink) {
        let model = scroll.layer.bounds
        let presentation = scroll.layer.presentation()?.bounds
        let inset = scroll.adjustedContentInset
        let guide = probe.guideFrame(window: window)
        var values: [CGFloat] = [model.minX, model.minY, model.width, model.height,
            scroll.bounds.minX, scroll.bounds.minY, scroll.bounds.width, scroll.bounds.height,
            scroll.contentOffset.x, scroll.contentOffset.y,
            scroll.contentSize.width, scroll.contentSize.height, inset.top, inset.left, inset.bottom, inset.right,
            guide.minX, guide.minY, guide.width, guide.height]
        if let presentation { values += [presentation.minX, presentation.minY, presentation.width, presentation.height] }
        let modelMatchesPresentation = presentation.map {
            abs(model.minX - $0.minX) <= 0.5 && abs(model.minY - $0.minY) <= 0.5
                && abs(model.width - $0.width) <= 0.5 && abs(model.height - $0.height) <= 0.5
        } ?? false
        let valid = scroll.window === window && probe.didShowLocalKeyboard && !probe.localKeyboardHideObservedAfterShow
            && responder?.isFirstResponder == true && values.allSatisfy(\.isFinite)
            && guide.height > 0 && scroll.bounds.height > 0 && scroll.contentSize.height > 0
            && !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating && !scroll.isScrollAnimating
            && modelMatchesPresentation
        let unchanged = previous.map { $0.count == values.count && zip($0, values).allSatisfy { abs($0.0 - $0.1) <= 0.5 } } ?? false
        stableFrames = valid ? (unchanged ? stableFrames + 1 : 1) : 0
        if !valid { previous = nil } else if !unchanged { previous = values }
        isStable = stableFrames >= 3
        trace.append(["timestamp": link.timestamp, "modelBounds": String(describing: model),
            "presentationBounds": String(describing: presentation), "adjustedInsets": String(describing: inset),
            "contentSize": String(describing: scroll.contentSize), "contentOffset": String(describing: scroll.contentOffset),
            "keyboardGuide": String(describing: guide), "ownedWindow": scroll.window === window,
            "isTracking": scroll.isTracking, "isDragging": scroll.isDragging, "isDecelerating": scroll.isDecelerating,
            "isScrollAnimating": scroll.isScrollAnimating, "modelMatchesPresentation": modelMatchesPresentation,
            "valid": valid, "stableFrames": stableFrames, "stable": isStable])
    }
}

/// UIViewの実geometryだけを観測する。仮想AXの全row取得や全animation停止を仮定しない。
@MainActor
private final class SnapshotListGeometryObserver: NSObject {
    private let window: UIWindow
    private var link: CADisplayLink?
    private var previous: [CGFloat]?
    private var previousIdentity: ObjectIdentifier?
    private var stableSince: TimeInterval?
    private var stableFrames = 0
    private var trace: [[String: Any]] = []
    private(set) var isStable = false
    // DSMotion.disclosureの250msと同じ連続安定期間。経過だけでは成功にしない。
    private let requiredStableInterval: TimeInterval = 0.25

    init(window: UIWindow) { self.window = window }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    func writeTrace(to url: URL, result: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["result": result, "requiredStableInterval": requiredStableInterval, "samples": trace], options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
    private func reset() { previous = nil; previousIdentity = nil; stableSince = nil; stableFrames = 0; isStable = false }
    @objc private func sample(_ link: CADisplayLink) {
        @MainActor
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        let scrolls = views(window).compactMap { $0 as? UIScrollView }.filter {
            $0.window === window && !$0.isHidden && $0.alpha > 0 && $0.bounds.width >= window.bounds.width * 0.5
        }
        guard let scroll = scrolls.max(by: { $0.contentSize.height < $1.contentSize.height }),
              let body = scroll.subviews.filter({ !$0.isHidden && $0.bounds.width >= scroll.bounds.width * 0.5 }).max(by: { $0.bounds.height < $1.bounds.height }) else {
            reset(); trace.append(["timestamp": link.timestamp, "valid": false, "reason": "expanded scroll body unavailable"]); return
        }
        let inset = scroll.adjustedContentInset
        let values: [CGFloat] = [scroll.bounds.width, scroll.bounds.height, scroll.contentSize.width, scroll.contentSize.height,
                                 inset.top, inset.left, inset.bottom, inset.right, scroll.contentOffset.x, scroll.contentOffset.y,
                                 body.frame.minX, body.frame.minY, body.frame.width, body.frame.height]
        let viewport = scroll.bounds.height - inset.top - inset.bottom
        let valid = values.allSatisfy(\.isFinite) && viewport.isFinite && viewport > 0
            && scroll.contentSize.height > viewport + 1 && body.frame.height > viewport + 1
        guard valid else {
            reset(); trace.append(["timestamp": link.timestamp, "valid": false, "valuesAsText": values.map { String(describing: $0) }]); return
        }
        let identity = ObjectIdentifier(scroll)
        let unchanged = previousIdentity == identity && previous.map { zip($0, values).allSatisfy { pair in abs(pair.0 - pair.1) <= 0.5 } } == true
        if unchanged {
            stableFrames += 1
        } else {
            stableSince = link.timestamp; stableFrames = 1
            previous = values; previousIdentity = identity
        }
        let elapsed = link.timestamp - (stableSince ?? link.timestamp)
        isStable = stableFrames >= 3 && elapsed >= requiredStableInterval
        trace.append(["timestamp": link.timestamp, "valid": true, "scrollIdentity": String(describing: identity),
                      "values": values.map(Double.init), "stableFrames": stableFrames, "stableInterval": elapsed,
                      "expandedBodyPresent": true, "overflow": true, "stable": isStable])
    }
}
