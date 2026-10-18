// ImageRenderer は NavigationStack を含む画面を正しく描けないため、UIWindow の drawHierarchy を使う。
// 入力操作は行わず、画面サイズ・安全領域・配色・文字サイズを指定して描画する。
import SwiftUI
import UIKit
import Testing
import AgentDomain
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
        let output = try outputDirectory(variables: variables)
        let iOSMajor = UIDevice.current.systemVersion.split(separator: ".").first ?? "unknown"
        let osSuffix = "-ios\(iOSMajor)"

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
                .frame(width: size.width, height: size.height)

                let safeArea = width == 428
                    ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                let scale: CGFloat = width == 428 ? 3 : 2
                let image = try await windowImage(
                    content,
                    size: size,
                    safeArea: safeArea,
                    scale: scale,
                    dark: dark
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
                let session = try #require(list.session(id: "attention-approval"))
                let detail = SessionDetailViewModel(session: session, api: environment.apiClient)
                await detail.load()
                try #require(detail.showsChat)
                detailModel = detail
            }

            let settings = AppSettings(store: InMemoryAppSettingsStore(appearance: .system))
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
                onAddSession: { _ in }
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
                        onQRScan: {}
                    )
                }
                .dsCampNavigationChrome()
            }
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: 428, height: 926)

            let size = CGSize(width: 428, height: 926)
            print("rendering shell snapshot: \(screen.rawValue)")
            let image = try await windowImage(
                content,
                size: size,
                safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                scale: 3,
                dark: false
            )
            try writeSnapshot(
                image,
                name: "\(screen.fileName)-428x926-light\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: 3
            )
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
                [(375, 667, false, false)]
            case .listDT:
                [(428, 926, false, true)]
            default:
                [(428, 926, false, false)]
            }

            for layout in layouts {
                let themeID = AppearancePreference.system.themeID(systemColorScheme: layout.dark ? .dark : .light)
                preferences.set(themeID, forKey: ThemeStore.themeKey)
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
                let size = CGSize(width: layout.width, height: layout.height)
                let expandedGroups: Set<String>? = screen == .listCollapsed ? ["id:simple-budget"] : nil
                let expandedSessions: Set<String> = screen == .listChildrenExpanded ? ["refactor", "csv-import"] : []
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
                    NavigationStack { sessionList }
                        .dsCampNavigationChrome()
                } settings: {
                    NavigationStack {
                        SettingsView(
                            viewModel: SettingsViewModel(settings: settings),
                            connectionViewModel: connection,
                            onQRScan: {}
                        )
                    }
                    .dsCampNavigationChrome()
                }
                .environment(\.colorScheme, layout.dark ? .dark : .light)
                .environment(\.dynamicTypeSize, layout.ax5 ? .accessibility5 : .large)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .frame(width: size.width, height: size.height)

                let safeArea = layout.width == 428
                    ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                let scale: CGFloat = layout.width == 428 ? 3 : 2
                let image = try await windowImage(
                    content,
                    size: size,
                    safeArea: safeArea,
                    scale: scale,
                    dark: layout.dark
                )
                try writeSnapshot(
                    image,
                    name: "\(screen.snapshotName)-\(Int(layout.width))x\(Int(layout.height))-\(layout.dark ? "dark" : "light")\(layout.ax5 ? "-ax5" : "")\(osSuffix).png",
                    to: output,
                    expectedSize: size,
                    expectedScale: scale
                )
            }
        }

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
                scale: 3,
                dark: dark
            )
            try writeSnapshot(
                image,
                name: "components-428x926-\(dark ? "dark" : "light")\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: 3
            )
        }

        let inputScenarios: [InputBarSnapshotScenario] = [
            .init(name: "ReplyEmpty"),
            .init(name: "ReplyTyping", text: "ProxyRouterTests の失敗 3 件を先に直して。\n直したら swift test をもう一度流して、結果だけ教えて"),
            .init(name: "ReplyRunEmpty", isRunning: true),
            .init(name: "ReplyRunText", text: "ProxyRouterTests の失敗 3 件を先に直して。\n直したら swift test をもう一度流して、結果だけ教えて", isRunning: true),
            .init(name: "ReplySending", isSending: true),
            .init(name: "ReplyPermDanger", permission: "bypassPermissions"),
            .init(name: "ReplyPermFail", permission: "manual", settingsError: "権限を変更できませんでした。今の権限（Manual）のままです。もう一度選んでください"),
            .init(name: "ReplyMore", width: 375, height: 667),
            .init(name: "ReplyHaiku", modelName: "Haiku 5.5", showsEffort: false),
            .init(name: "ReplyInputDT", isAccessibilitySize: true),
            .init(name: "ReplyAttach", text: "この2枚の502の画面を見て原因を探して [Image #1] [Image #2]", attachmentCount: 2),
            .init(
                name: "ReplyAttachErr",
                text: "ログの画面 [Image #1] [Image #2] [Image #3] [Image #4]",
                attachmentCount: 4,
                attachmentError: "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。"
            ),
            .init(name: "ReplyDark", dark: true),
            .init(name: "UsageNormal"),
            .init(name: "UsageLow", usageStyle: .low),
            .init(name: "UsageNa", usageStyle: .unavailable),
            .init(name: "UsageStale", usageState: .failed),
            .init(name: "UsageRefresh", usageState: .loading),
            .init(name: "UsageNormalDT", isAccessibilitySize: true),
            .init(name: "UsageNormalDark", dark: true),
            .init(name: "UsagePop", showsUsagePopover: true),
            .init(name: "UsagePopDark", dark: true, showsUsagePopover: true),
        ]

        let attachmentPreviews = [
            snapshotAttachmentData(color: UIColor(red: 0.82, green: 0.82, blue: 0.87, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.55, green: 0.75, blue: 0.63, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.88, green: 0.73, blue: 0.62, alpha: 1)),
            snapshotAttachmentData(color: UIColor(red: 0.56, green: 0.67, blue: 0.82, alpha: 1)),
        ]
        for scenario in inputScenarios {
            let themeID = AppearancePreference.system.themeID(systemColorScheme: scenario.dark ? .dark : .light)
            preferences.set(themeID, forKey: ThemeStore.themeKey)
            DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            let size = CGSize(width: scenario.width, height: scenario.height)
            let safeArea = scenario.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let content: AnyView
            let attachments = (0..<scenario.attachmentCount).map { index in
                let number = index + 1
                return DSAttachmentStripItem(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
                    number: number,
                    previewData: attachmentPreviews[index % attachmentPreviews.count]
                )
            }
            let settings = inputBarSettings(
                permission: scenario.permission,
                showsEffort: scenario.showsEffort
            )
            let inputBar = DSInputBar(
                text: .constant(scenario.text),
                placeholder: "やりたいことを入力",
                isLoading: scenario.isSending,
                attachmentStrip: attachments,
                attachmentError: scenario.attachmentError,
                settingsError: scenario.settingsError,
                contextLabel: "Phlox",
                onAddAttachments: { _ in },
                onRemoveAttachment: { _ in },
                isRunning: scenario.isRunning,
                onStop: {},
                model: (kind: .claudeCode, displayName: scenario.modelName),
                settings: settings,
                onSubmit: {}
            )
            let usageViewModel = UsageViewModel(
                api: UITestSnapshotUsageAPI(),
                agents: UITestUsageFixtures.values(for: scenario.usageStyle),
                state: scenario.usageState,
                lastSuccessfulAt: scenario.usageLastSuccessfulAt,
                now: { UITestUsageFixtures.asOfDate }
            )
            let usageRow = UsageRingRow(
                viewModel: usageViewModel,
                isPopoverPresented: scenario.showsUsagePopover
            )
            .padding(.horizontal, DSSpacing.xl)
            content = AnyView(
                ZStack(alignment: .bottom) {
                    snapshotTranscript(for: scenario)
                        .frame(width: size.width, height: size.height)
                    VStack(spacing: DSSpacing.s) {
                        inputBar
                        usageRow
                    }
                    .padding(.bottom, DSSpacing.m)
                }
                .frame(width: size.width, height: size.height)
                .background(DSColor.background)
                .environment(\.colorScheme, scenario.dark ? .dark : .light)
                .environment(\.dynamicTypeSize, scenario.isAccessibilitySize ? .accessibility5 : .large)
                .environment(\.locale, Locale(identifier: "ja_JP"))
            )

            let scale: CGFloat = scenario.width == 428 ? 3 : 2
            let image = try await windowImage(
                content,
                size: size,
                safeArea: safeArea,
                scale: scale,
                dark: scenario.dark
            )
            try writeSnapshot(
                image,
                name: "\(scenario.name)-\(Int(scenario.width))x\(Int(scenario.height))-\(scenario.dark ? "dark" : "light")\(scenario.isAccessibilitySize ? "-ax5" : "")\(osSuffix).png",
                to: output,
                expectedSize: size,
                expectedScale: scale
            )
        }

        let modelEntries = [
            SessionDetailViewModel.ModelPickerEntry(kind: .claudeCode, modelID: "opus", displayName: "Opus (1M context)"),
            SessionDetailViewModel.ModelPickerEntry(kind: .claudeCode, modelID: "sonnet", displayName: "Sonnet 5"),
            SessionDetailViewModel.ModelPickerEntry(kind: .claudeCode, modelID: "haiku", displayName: "Haiku 5.5"),
        ]
        let modelThemeID = AppearancePreference.system.themeID(systemColorScheme: .light)
        preferences.set(modelThemeID, forKey: ThemeStore.themeKey)
        DSNavigationChrome.installUIKitAppearanceIfNeeded(for: modelThemeID)
        let selectedModelID = modelEntries[1].id
        let modelSheetContent = ModelPickerSnapshotHost(
            entries: modelEntries,
            selectedEntryID: selectedModelID,
            agentName: AgentKind.claudeCode.displayName,
            defaultEntryID: modelEntries[0].id
        )
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .frame(width: 428, height: 926)
        let modelImage = try await windowImage(
            modelSheetContent,
            size: CGSize(width: 428, height: 926),
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            scale: 3,
            dark: false
        )
        try writeSnapshot(
            modelImage,
            name: "ReplyModel-428x926-light\(osSuffix).png",
            to: output,
            expectedSize: CGSize(width: 428, height: 926),
            expectedScale: 3
        )

        try await renderNewChatSnapshots(output: output, variables: variables, osSuffix: osSuffix)
    }

    @Test func dotGothic16FontAndLicenseAreInHostedApp() throws {
        #expect(UIFont(name: "DotGothic16-Regular", size: 28) != nil)
        let licenseURL = try #require(Bundle.main.url(forResource: "OFL", withExtension: "txt"))
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(!license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func renderSessionDetailSnapshots(output: URL, osSuffix: String) async throws {
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
            text: "転送処理が ControlServer と MobileProxy の 2 か所にあります。ProxyRouter を新設して 1 か所にまとめます。"
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
            text: "### 変更点\n\n- `ProxyRouter` を新設し、/sessions と /approvals の転送をまとめた\n- ControlServer からは転送処理を削除\n- 既存テスト 50 件はすべて成功\n\n経緯は ADR 0044 にまとめました。呼び出し側はこう変わります。\n\n```swift\nlet router = ProxyRouter(upstream: config.upstream)\nserver.mount(\"/sessions\", router.handler)\nserver.mount(\"/approvals\", router.handler)\n```\n\n| エンドポイント | 変更前 | 変更後 |\n| --- | --- | --- |\n| /sessions/* | ControlServer | ProxyRouter |\n| /approvals | ControlServer | ProxyRouter |\n| /usage | MobileProxy | MobileProxy |"
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
                    question: "失敗している 3 件のテストはどう扱いますか？", header: "CHECKS",
                    options: [UserQuestionOption(label: "lint"), UserQuestionOption(label: "unit tests"), UserQuestionOption(label: "UI tests")],
                    multiSelect: true
                ),
            ],
            answers: [
                "どの環境で動作確認しますか？": ["staging"],
                "失敗している 3 件のテストはどう扱いますか？": ["lint", "unit tests"],
            ], state: .pending
        )
        let plainQuestion = ChatMessage.userQuestion(
            id: "plain-question", requestId: "plain-question-request",
            questions: [UserQuestionItem(
                question: "/approvals のレスポンス契約は v2（id・session・kind・prompt）で進めますか？",
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
        let codexApprovalTwo = Approval(
            id: "reply-codex-two", sessionID: detailSession.id, kind: .codex,
            prompt: "ControlServer.swift を削除します。", actionKind: "fileChange"
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
        let attachmentPreviews = [
            snapshotAttachmentData(color: .systemOrange, label: "502"),
            snapshotAttachmentData(color: .systemBlue, label: "LOG"),
        ]
        let cases: [SessionDetailSnapshotCase] = [
            .init(name: detailName, session: detailSession, messages: .success(detailRecentMessages), approvals: [approval]),
            .init(name: "ChatLoading", session: chatSession("loading", .running), messages: .suspended),
            .init(name: "ChatEmpty", session: chatSession("empty", .idle), messages: .success([])),
            .init(name: "ChatFetchErr", session: chatSession("fetch-error", .running), messages: .failure(.server(status: 502, message: "gateway timeout"))),
            .init(name: "ChatUnsupported", session: Session(id: "pty", name: chatName, agent: .claudeCode, status: .running, backend: "pty", updatedAt: snapshotDate), messages: .success(stallMessages)),
            .init(name: "ChatSendFail", session: chatSession("send-failed", .idle), messages: .success([lastToolCommands[0], lastToolCommands[1], lastToolCommands[2], richReply]), recovery: SessionDetailRecovery(text: "失敗しているテストを先に直して", attachments: [], errorMessage: "送信に失敗しました · Mac に接続できません"), isNewSession: true),
            .init(name: "Chat", session: chatSession("chat", .running), messages: .success(runningMessages), attachmentPreviews: ["chat-user": attachmentPreviews], statusAge: 38),
            .init(name: "ChatStall", session: chatSession("stalled", .running, stalled: true), messages: .success(stallMessages), attachmentPreviews: ["chat-user": attachmentPreviews]),
            .init(name: "ChatIdle", session: chatSession("idle", .idle), messages: .success(idleMessages), usage: usage42),
            .init(name: "ChatDone", session: chatSession("done", .completed(exitCode: 0)), messages: .success(doneMessages), usage: usage16),
            .init(name: "ChatError", session: chatSession("error", .error(message: "ProxyRouterTests failed")), messages: .success(chatErrorMessages)),
            .init(name: "ChatQuestion", session: chatSession("question", .awaitingUserQuestion), messages: .success([answeredScope, agent, .command(id: "question-tests", command: testCommand, output: testOutput), .error(id: "question-error", message: "3 件のテストが失敗しています（ProxyRouterTests）。"), pendingDeploymentQuestion]), statusAge: 12),
            .init(name: "ChatExpandCmd", session: chatSession("expand-cmd", .running), messages: .success([agent] + lastToolCommands + [buildMessage]), expandedMessageIDs: ["chat-tool-edit", "chat-tool-tests"], statusAge: 12),
            .init(name: "ChatExpandDiff", session: chatSession("expand-diff", .idle), messages: .success([agent, fileA, fileB, .turnCost(id: "chat-turn-cost", costUSD: 0.42)]), usage: usage42, expandedMessageIDs: ["chat-file-a-file-0", "chat-file-b-file-0"]),
            .init(name: "ChatThinking", session: chatSession("thinking", .running), messages: .success([userFirst, reasoning, readCommands[0], readCommands[1], agent, expandedReasoning]), attachmentPreviews: ["chat-user": attachmentPreviews], expandedMessageIDs: ["chat-reasoning-expanded"], statusAge: 12),
            .init(name: "ReplyStarting", session: chatSession("starting", .starting), messages: .success([.command(id: "starting-command", command: "phlox spawn --agent claude-code --project ControlServer", output: "実行中"), .agent(id: "starting-message", text: "セッションを準備しています。")]), isNewSession: true),
            .init(name: "Reply", session: replySession, messages: .success(replyMessages), statusAge: 120),
            .init(name: "ReplyCodex", session: detailSession, messages: .success(codexReplyMessages), approvals: [codexApprovalOne], statusAge: 120),
            .init(name: "ReplyApprovalDiff", session: detailSession, messages: .success([codexDiffMessage]), approvals: [codexDiffApproval], statusAge: 60, replyState: .expandedApprovalDiff),
            .init(name: "ReplyApprovalFail", session: replySession, messages: .success(replyMessages), statusAge: 120, replyState: .approvalFailure),
            .init(name: "ReplyDT", session: replySession, messages: .success(replyMessages), statusAge: 120, isAccessibilitySize: true),
            .init(name: "FlowApprove", session: detailSession, messages: .success(codexReplyMessages), approvals: [codexApprovalOne], statusAge: 120),
            .init(name: "FlowNext", session: detailSession, messages: .success(codexReplyMessages), approvals: [codexApprovalOne, codexApprovalTwo], statusAge: 120, replyState: .approvalResult(actionLabel: "許可", remainingCount: 1)),
            .init(name: "ReplyQuestion", session: chatSession("reply-question", .awaitingUserQuestion), messages: .success([agent, .command(id: "reply-question-tests", command: testCommand, output: testOutput), pendingDeploymentQuestion]), statusAge: 12),
            .init(name: "ReplyQuestionPlain", session: chatSession("reply-question-plain", .awaitingUserQuestion), messages: .success([agent, plainQuestion]), statusAge: 12),
            .init(name: "ReplyQuestionFail", session: chatSession("reply-question-fail", .awaitingUserQuestion), messages: .success([agent, .command(id: "reply-question-fail-tests", command: testCommand, output: testOutput), pendingDeploymentQuestionFail]), statusAge: 12, replyState: .questionFailure(requestID: "deploy-test-request")),
        ]

        let environment = AppEnvironment.uiTesting(scenario: .goldenPath)
        let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
        await list.observe()
        defer { list.stop() }

        for snapshot in cases {
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
                readiness: readiness
            )
            let navigationState = SessionNavigationState.resolve(
                listState: list.state, lastKnownSessions: list.lastKnownSessions, reachability: .online
            )
            let size = CGSize(width: 428, height: 926)
            let content = SessionDetailSnapshotHost(
                list: list, navigationState: navigationState, snapshot: snapshot,
                session: session, api: api
            )
            .environment(\.usageViewModel, UsageViewModel(
                api: api, agents: UITestUsageFixtures.values(for: .normal), state: .loaded,
                lastSuccessfulAt: UITestUsageFixtures.asOfDate, now: { UITestUsageFixtures.asOfDate }
            ))
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, snapshot.isAccessibilitySize ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: size.width, height: size.height)

            let image = try await windowImage(
                content, size: size,
                safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
                scale: 2, dark: false, settleDelay: .milliseconds(800),
                waitUntilReady: {
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
                }
            )
            try writeSnapshot(
                image, name: "\(snapshot.name)-428x926-light\(osSuffix).png", to: output,
                expectedSize: size, expectedScale: 2
            )
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
        osSuffix: String
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
            Layout(name: "DraftModel", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftModelNa", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftPermDanger", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftMoreSE", width: 375, height: 667, dark: false, ax5: false),
            Layout(name: "DraftCreating", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftFailed", width: 428, height: 926, dark: false, ax5: false),
            Layout(name: "DraftSE", width: 375, height: 667, dark: false, ax5: false),
            Layout(name: "DraftDT", width: 428, height: 926, dark: false, ax5: true),
            Layout(name: "DraftDark", width: 428, height: 926, dark: true, ax5: false),
        ]

        for layout in layouts {
            let suiteName = "Phlox.NewChatSnapshot.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = NewChatSettingsStore(defaults: defaults)
            store.record(
                kind: .claudeCode,
                model: "sonnet",
                effort: "high",
                permission: "manual",
                planMode: false,
                projectKey: layout.name == "DraftEntryEmpty" ? "deleted-project" : "project-phlox"
            )

            let entry: SessionComposeDraft = layout.name == "DraftFromProject"
                ? SessionComposeDraft(project: "SimpleBudget", projectID: "project-simple-budget")
                : SessionComposeDraft(project: "")
            let api = NewChatSnapshotAPI(cursorUnavailable: layout.name == "DraftModelNa")
            let viewModel = NewChatViewModel(api: api, entryProject: entry, settingsStore: store)
            await viewModel.load()

            let greeting: String = switch layout.name {
            case "DraftFromProject": "次は何を作りますか？"
            case "DraftSuggest": "今日の課題を教えてください"
            case "DraftEntryEmpty": "何をお手伝いしましょうか？"
            case "DraftSE": "さあ、始めましょう"
            case "DraftDT": "アイデアを形にしましょう"
            case "DraftDark": "今日は何を進めますか？"
            case "DraftFailed": "さあ、始めましょう"
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
            case "DraftModel", "DraftModelNa":
                viewModel.isModelPickerPresented = true
            case "DraftPermDanger":
                viewModel.inputText = "CI の設定を直して、通るまで回して"
                viewModel.inputCursorUTF16 = viewModel.inputText.utf16.count
                viewModel.selectPermission("bypassPermissions")
            case "DraftMoreSE":
                showsMoreSettings = true
            case "DraftCreating":
                viewModel.seedProgressForSnapshot(text: "ProxyRouter のテストを流して、落ちたら直して", waitSeconds: 4)
            case "DraftFailed":
                viewModel.seedCreationErrorForSnapshot(
                    "セッションを作成できませんでした。指示は入力欄に戻しました（workspace \"phlox\" is locked by another spawn）",
                    text: "ProxyRouter のテストを流して、落ちたら直して"
                )
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
                showsMoreSettings: showsMoreSettings,
                dark: layout.dark,
                ax5: layout.ax5
            )
            .environment(\.colorScheme, layout.dark ? .dark : .light)
            .environment(\.dynamicTypeSize, layout.ax5 ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(width: size.width, height: size.height)

            let safeArea = layout.width == 428
                ? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
                : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
            let scale: CGFloat = layout.width == 428 ? 3 : 2
            let image = try await windowImage(
                content,
                size: size,
                safeArea: safeArea,
                scale: scale,
                dark: layout.dark,
                settleDelay: .milliseconds(100)
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

    private func windowImage<Content: View>(
        _ content: Content,
        size: CGSize,
        safeArea: UIEdgeInsets,
        scale: CGFloat,
        dark: Bool,
        settleDelay: Duration = .milliseconds(20),
        waitUntilReady: (() async -> Void)? = nil
    ) async throws -> UIImage {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.isHidden = false
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
        await waitUntilReady?()
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
        let debugURL = debugDirectory.appendingPathComponent("body-failure-\(Int(size.width))x\(Int(size.height))-ios\(osMajor).png")
        let debugPNG = try #require(lastImage?.pngData())
        try debugPNG.write(to: debugURL, options: .atomic)
        print("snapshot body failure image: \(debugURL.path)")
        throw SnapshotError.bodyDidNotRender
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
        let bodyRegions = [height / 4..<height * 3 / 4, height / 12..<height * 7 / 12]
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

    private func inputBarSettings(
        permission: String,
        showsEffort: Bool
    ) -> DSInputBarSettings {
        DSInputBarSettings(
            agentName: "Claude Code",
            effortOptions: showsEffort ? [
                DSInputBarSettingOption(value: "low", displayName: "低"),
                DSInputBarSettingOption(value: "medium", displayName: "中"),
                DSInputBarSettingOption(value: "high", displayName: "高"),
            ] : [],
            selectedEffort: showsEffort ? "high" : nil,
            permissionOptions: [
                DSInputBarSettingOption(value: "manual", displayName: "Manual"),
                DSInputBarSettingOption(value: "acceptEdits", displayName: "Accept Edits"),
                DSInputBarSettingOption(value: "auto", displayName: "Auto"),
                DSInputBarSettingOption(value: "bypassPermissions", displayName: "Bypass Permissions"),
            ],
            selectedPermission: permission,
            planModeAvailable: true
        )
    }

    private func snapshotTranscript(for scenario: InputBarSnapshotScenario) -> some View {
        let usageBoard = scenario.name.hasPrefix("Usage")
        let runningBoard = scenario.name == "ReplyRunText"
        let command = usageBoard
            ? "コマンド  $ swiftlint lint --strict"
            : "コマンド  $ swift test --package-path mobile …\(runningBoard ? " 実行中" : " exit 0")"
        let assistantText = usageBoard
            ? "lint の指摘 3 件を直しました。テストと lint はすべて通っています。"
            : runningBoard
                ? "ProxyRouter を追加しました。テストを実行します。"
                : "テストは 50 件すべて成功しました。次は何をしますか？"

        return VStack(alignment: .leading, spacing: DSSpacing.l) {
            Spacer(minLength: 0)
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "chevron.right")
                    .font(DSFont.captionStrong)
                    .foregroundStyle(DSColor.textSecondary)
                Text(command)
                    .font(.system(size: 14, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
            .background(DSColor.chatCard, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            Text(assistantText)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
            if usageBoard {
                Text("$0.42 · 入力 18.2k · 出力 1.9k · コンテキスト 22%")
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if runningBoard {
                Text("実行中…  swift test を実行中 · 38 秒")
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 150)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func snapshotAttachmentData(color: UIColor, label: String? = nil) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            if let label {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                let textSize = (label as NSString).size(withAttributes: attributes)
                (label as NSString).draw(
                    at: CGPoint(x: (64 - textSize.width) / 2, y: (64 - textSize.height) / 2),
                    withAttributes: attributes
                )
            }
        }
    }

    private enum SnapshotError: Error { case bodyDidNotRender }
}

private struct SessionDetailSnapshotCase {
    let name: String
    let session: Session
    let messages: SessionDetailSnapshotMessages
    var approvals: [Approval] = []
    var usage: TurnUsage?
    var recovery: SessionDetailRecovery?
    var isNewSession = false
    var attachmentPreviews: [String: [Data]] = [:]
    var expandedMessageIDs: Set<String> = []
    var statusAge: TimeInterval?
    var isAccessibilitySize = false
    var replyState: SessionDetailViewModel.ReplySnapshotState?
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
                        SessionDetailDestination(
                            session: session, api: api, recovery: snapshot.recovery,
                            isNewSession: snapshot.isNewSession,
                            initialAttachmentPreviews: snapshot.attachmentPreviews,
                            initialExpandedMessageIDs: snapshot.expandedMessageIDs,
                            snapshotReplyState: snapshot.replyState,
                            onDelete: {}
                        )
                        .toolbar(.hidden, for: .tabBar)
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

private struct SessionDetailSnapshotAPI: PhloxAPI, SessionModelSelecting {
    let session: Session
    let messages: SessionDetailSnapshotMessages
    let approvals: [Approval]
    let turnUsage: TurnUsage?
    let readiness: SessionDetailSnapshotReadiness?

    private var model: SessionModelOption {
        if session.agent == .codex {
            return SessionModelOption(id: "gpt-6.1-sol", displayName: "gpt-6.1-sol")
        }
        return SessionModelOption(id: "sonnet-5", displayName: "Sonnet 5")
    }

    func listSessions() async throws -> [Session] { [session] }
    func usage(sessionID: String) async throws -> TurnUsage? { turnUsage }
    func spawn(_ request: SpawnRequest) async throws -> Session { session }
    func agentSettings(kind: AgentKind) async throws -> AgentSettings? { nil }
    func projects() async throws -> [ProjectSummary]? { [] }
    func cliUsage() async throws -> [CLIUsage] { UITestUsageFixtures.values(for: .normal) }
    func agentModels(kind: AgentKind) async throws -> AgentModels { AgentModels(models: [model], defaultModel: model.id) }
    func sessionSettings(sessionID: String) async throws -> SessionModelSettings {
        SessionModelSettings(
            selectedModel: model.id,
            availableModels: [model],
            selectedEffort: session.agent == .codex ? "medium" : "high",
            availableEfforts: session.agent == .codex
                ? [
                    AgentSettingOption(value: "low", displayName: "低"),
                    AgentSettingOption(value: "medium", displayName: "中"),
                    AgentSettingOption(value: "high", displayName: "高"),
                ]
                : [AgentSettingOption(value: "high", displayName: "高")],
            selectedPermission: session.agent == .codex ? nil : "acceptEdits",
            availablePermissions: session.agent == .codex
                ? [AgentSettingOption(value: nil, displayName: "Default")]
                : [AgentSettingOption(value: "acceptEdits", displayName: "Accept Edits")],
            planMode: false,
            planModeAvailable: true
        )
    }
    func setModel(sessionID: String, model: String) async throws {}
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
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

private actor SessionDetailSnapshotReadiness {
    private var messagesLoaded = false
    private var approvalsLoaded = false
    private var messageWaiter: CheckedContinuation<Void, Never>?
    private var approvalWaiter: CheckedContinuation<Void, Never>?

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
    let showsMoreSettings: Bool
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
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                NewChatView(
                                    viewModel: viewModel,
                                    fixedGreeting: greeting,
                                    focusOnAppear: false,
                                    onCreated: { _, _ in }
                                )
                                .environment(\.usageViewModel, usageViewModel)
                                .overlay {
                                    if showsMoreSettings {
                                        NewChatMoreSettingsSnapshotPanel()
                                            .position(
                                                x: geometry.size.width / 2,
                                                y: geometry.size.height * 0.58
                                            )
                                            .accessibilityHidden(true)
                                    }
                                }

                            }
                        }
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

/// Menu を合成操作で開かず、盤面にあるメニューの見た目を描画する専用 fixture。
private struct NewChatMoreSettingsSnapshotPanel: View {
    var body: some View {
        VStack(spacing: 0) {
            settingRow(title: "思考の強さ", value: "高", symbol: "gauge.medium")
            Rectangle()
                .fill(IOSColor.bg.separator)
                .frame(height: 1)
            settingRow(title: "権限", value: "Manual", symbol: "shield")
        }
        .padding(.horizontal, 14)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(IOSColor.bg.separator.opacity(0.7), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func settingRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(DSFont.body.weight(.medium))
                .foregroundStyle(IOSColor.text.primary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(IOSColor.text.primary)
                Text(value)
                    .font(DSFont.subheadline)
                    .foregroundStyle(IOSColor.text.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(DSFont.captionStrong)
                .foregroundStyle(IOSColor.text.secondary)
        }
        .frame(height: 51)
    }
}

private struct NewChatSnapshotAPI: PhloxAPI {
    let cursorUnavailable: Bool

    func listSessions() async throws -> [Session] { [] }

    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(
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
        if kind == .cursor && cursorUnavailable {
            throw PhloxError.server(status: 503, message: "取得できません")
        }
        switch kind {
        case .claudeCode:
            return AgentModels(models: [
                SessionModelOption(id: "opus", displayName: "Opus (1M context)"),
                SessionModelOption(id: "sonnet", displayName: "Sonnet 5"),
            ], defaultModel: "sonnet")
        case .codex:
            return AgentModels(models: [
                SessionModelOption(id: "gpt-6.1-sol", displayName: "gpt-6.1-sol"),
                SessionModelOption(id: "gpt-6.1-codex", displayName: "gpt-6.1-codex"),
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

private struct ModelPickerSnapshotHost: View {
    let entries: [SessionDetailViewModel.ModelPickerEntry]
    let selectedEntryID: String?
    let agentName: String
    let defaultEntryID: String?

    @State private var isPresented = false

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Text("テストの出力を確認しています")
                    .font(DSFont.body)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.background)
        }
        .sheet(isPresented: $isPresented) {
            ModelPickerSheet(
                entries: entries,
                selectedEntryID: selectedEntryID,
                agentName: agentName,
                defaultEntryID: defaultEntryID,
                isChangingModelID: nil,
                failureMessage: nil,
                onSelect: { _ in },
                onDismiss: {}
            )
            .presentationDetents([.height(680)])
            .presentationDragIndicator(.visible)
        }
        .task {
            await Task.yield()
            isPresented = true
        }
    }
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
        showsUsagePopover: Bool = false
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
    }
}

private struct UITestSnapshotUsageAPI: PhloxAPI {
    func listSessions() async throws -> [Session] { [] }
    func spawn(_ request: SpawnRequest) async throws -> Session {
        Session(id: "snapshot", name: "snapshot", agent: request.agent, status: .starting, subtitle: "", updatedAt: .distantPast)
    }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
    func cliUsage() async throws -> [CLIUsage] { UITestUsageFixtures.values(for: .normal) }
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
