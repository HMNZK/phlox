// ImageRenderer は NavigationStack を含む画面を正しく描けないため、UIWindow の drawHierarchy を使う。
// 入力操作は行わず、画面サイズ・安全領域・配色・文字サイズを指定して描画する。
import SwiftUI
import UIKit
import Testing
import AgentDomain
import Features
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
            if Double(foreground) / Double(max(1, samples.count)) > 0.015 && rows.count >= 4 {
                return true
            }
        }
        return false
    }

    private enum SnapshotError: Error { case bodyDidNotRender }
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
