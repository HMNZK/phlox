// ImageRenderer はこの2画面の NavigationStack を描けず黄色の禁止マークになった。
// 本文の画素検査でこれを拒否し、UIWindow + UIHostingController の drawHierarchy に切り替える。
// 入力操作は行わず、画面サイズ・配色・文字サイズを指定して描画する。
import SwiftUI
import UIKit
import Testing
import Features
import PhloxCore
import DesignSystemIOS
@testable import PhloxMobile

@MainActor
struct DesignSnapshotRenderTests {
    @Test func renderDesignSnapshots() async throws {
        let variables = ProcessInfo.processInfo.environment
        guard variables["PHLOX_DESIGN_SNAPSHOTS"] == "1" else { return }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output: URL
        if let path = variables["PHLOX_SNAPSHOT_DIR"] {
            try #require(path.hasPrefix("/"), "PHLOX_SNAPSHOT_DIR must be absolute")
            output = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            output = root.appendingPathComponent(".verification/ios-redesign/snapshots", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

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
            let list = SessionListViewModel(repository: environment.sessionRepository)
            // 見本の有限ストリーム完了を待つ。固定時間の待機やデータの複製はしない。
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
                // AppRoot.synchronizeTheme と同じ対応。DSColor は colorScheme ではなくテーマを参照する。
                let themeID = AppearancePreference.system.themeID(systemColorScheme: dark ? .dark : .light)
                preferences.set(themeID, forKey: ThemeStore.themeKey)
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
                let size = CGSize(width: width, height: height)
                let content = NavigationStack {
                    if screen == .sessionList {
                        SessionListView(
                            viewModel: list, reachability: .online,
                            onSelectDetail: { _ in }, onAnswerQuestion: { _ in }, onAddSession: { _ in }
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

                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let image: UIImage
                if let candidate = renderer.uiImage, hasBodyContent(candidate) {
                    print("snapshot \(screen.rawValue): ImageRenderer")
                    image = candidate
                } else {
                    print("snapshot \(screen.rawValue): ImageRenderer has no body; using UIWindow")
                    image = try await windowImage(content, size: size, dark: dark)
                }
                try #require(hasBodyContent(image), "Blank or placeholder-only snapshot: \(screen.rawValue)")
                let name = "\(screen.rawValue)-\(width)x\(height)-\(dark ? "dark" : "light")\(ax5 ? "-ax5" : "").png"
                let url = output.appendingPathComponent(name)
                let png = try #require(image.pngData())
                try png.write(to: url, options: .atomic)
                #expect(FileManager.default.fileExists(atPath: url.path))
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                #expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > 0)
                #expect(image.size == size)
            }
        }
    }

    private func windowImage(_ content: some View, size: CGSize, dark: Bool) async throws -> UIImage {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            var drawn = false
            let image = renderer.image { _ in
                drawn = window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            if drawn && hasBodyContent(image) { return image }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        throw SnapshotError.bodyDidNotRender
    }

    // 中央の本文だけを検査し、ナビバーや入力欄だけの描画を成功としない。
    // 色を粗く量子化し、背景以外の画素が 1.5% 以上・複数行にあることを求める。
    // 黄色い禁止マークは本文画素に数えない。
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
        var colors: [Int: Int] = [:]
        var rows = Set<Int>()
        var samples: [(Int, Int)] = []
        for y in stride(from: height / 4, to: height * 3 / 4, by: 2) {
            for x in stride(from: width / 12, to: width * 11 / 12, by: 2) {
                let i = (y * width + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let yellow = r > 160 && g > 120 && b < 100
                let key = yellow ? -1 : (r / 32) * 64 + (g / 32) * 8 + b / 32
                colors[key, default: 0] += 1
                samples.append((key, y))
            }
        }
        guard let background = colors.max(by: { $0.value < $1.value })?.key else { return false }
        guard Double(colors[-1, default: 0]) / Double(max(1, samples.count)) < 0.01 else { return false }
        var foreground = 0
        for (key, y) in samples where key != background && key != -1 {
            foreground += 1
            rows.insert(y / 16)
        }
        return Double(foreground) / Double(max(1, samples.count)) > 0.015 && rows.count >= 4
    }

    private enum SnapshotError: Error { case bodyDidNotRender }
}
