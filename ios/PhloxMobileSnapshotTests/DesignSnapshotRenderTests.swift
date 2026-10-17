// ImageRenderer は NavigationStack を含む画面を正しく描けないため、UIWindow の drawHierarchy を使う。
// 入力操作は行わず、画面サイズ・安全領域・配色・文字サイズを指定して描画する。
import SwiftUI
import UIKit
import Testing
import AgentDomain
@testable import Features
import PhloxCore
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

        for screen in [UITestingSupport.Screen.sessionList, .sessionDetail] {
            let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: screen)
            let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
            await list.observe()
            try #require(!list.allSessions.isEmpty)
            defer { list.stop() }
            let session = try #require(list.session(id: "sess-rose"))
            let detail = SessionDetailViewModel(session: session, api: environment.apiClient)
            await detail.load()
            try #require(detail.showsChat)

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
                    if screen == .sessionList {
                        SessionListView(
                            viewModel: list, reachability: .online,
                            onSelectDetail: { _ in }, onAddSession: { _ in }
                        )
                    } else {
                        SessionDetailView(viewModel: detail, onDelete: {})
                    }
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
            .init(name: "ReplyStarting", isStarting: true),
            .init(name: "ReplyPermDanger", permission: "bypassPermissions"),
            .init(name: "ReplyPermFail", permission: "manual", settingsError: "権限を変更できませんでした。今の権限（Manual）のままです。もう一度選んでください"),
            .init(name: "ReplyMore", width: 375, height: 667),
            .init(name: "ReplyHaiku", modelName: "Haiku 5.5", showsEffort: false),
            .init(name: "ReplyDT", isAccessibilitySize: true),
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
            if scenario.isStarting {
                content = AnyView(
                    ZStack(alignment: .bottom) {
                        snapshotTranscript(for: scenario)
                            .frame(width: size.width, height: size.height)
                        HStack(spacing: DSSpacing.s) {
                            ProgressView().controlSize(.small)
                            Text("セッションを起動しています。準備ができると入力できます")
                                .font(DSFont.subheadline)
                                .foregroundStyle(IOSColor.text.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSSpacing.m)
                        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.bottom, DSSpacing.m)
                    }
                    .frame(width: size.width, height: size.height)
                    .background(DSColor.background)
                )
            } else {
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
            }

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
    }

    @Test func dotGothic16FontAndLicenseAreInHostedApp() throws {
        #expect(UIFont(name: "DotGothic16-Regular", size: 28) != nil)
        let licenseURL = try #require(Bundle.main.url(forResource: "OFL", withExtension: "txt"))
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(!license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        dark: Bool
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
        try await Task.sleep(for: .milliseconds(20))
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

    private func snapshotAttachmentData(color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }

    private enum SnapshotError: Error { case bodyDidNotRender }
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
    let isStarting: Bool
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
        isStarting: Bool = false,
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
        self.isStarting = isStarting
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
