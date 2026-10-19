import SwiftUI
import UIKit
import Vision
import CoreImage
import Testing
import PhloxCore
import DesignSystemIOS
@testable import Features
@testable import PhloxMobile

/// 本番native TabViewの実ウィンドウ描画。AX文字列と可視文字を別に検査する。
@MainActor
@Suite(.serialized)
struct OfflineAccessoryAcceptanceTests {
    @Test(arguments: OfflineScenario.all)
    func offlineAccessoryRemainsReadableInNativeTabHost(_ scenario: OfflineScenario) async throws {
        try #require(UITestingSupport.isEnabled)
        let environment = AppEnvironment.uiTesting(scenario: .goldenPath, screen: .listManyTop)
        let list = SessionListViewModel(repository: environment.sessionRepository, api: environment.apiClient)
        await list.observe()
        defer { list.stop() }
        try #require(list.lastKnownSessions.count > 10)
        let sizes: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
            ("large", .large, .large), ("ax1", .accessibility1, .accessibilityMedium),
            ("ax5", .accessibility5, .accessibilityExtraExtraExtraLarge),
        ]
                        let reachability: Reachability = scenario.host ? .unreachableHost : .offlineNetwork
                        let (sizeName, dynamicSize, nativeSize) = sizes[scenario.sizeIndex]
                        let width = scenario.width
                        let reconnecting = scenario.reconnecting
                        let lastFetchedAt = Date().addingTimeInterval(-180)
                        let name = "\(reachability == .unreachableHost ? "host" : "network")-\(sizeName)-\(width)-\(reconnecting ? "retrying" : "idle")"
                        let run = try OfflineRun(name: name)
                        let state = SessionNavigationState.resolve(listState: list.state, lastKnownSessions: list.lastKnownSessions, reachability: reachability)
                        let content = AppShellView(
                            selection: .constant(AppTab.sessions), navigationState: state,
                            reachability: reachability, lastFetchedAt: lastFetchedAt,
                            host: "100.64.0.1", hidesTabBar: false, hidesAccessory: false,
                            isReconnecting: reconnecting, onOpenSession: { _ in }, onShowSessionList: {},
                            onReconnect: { Issue.record("The rendering test must not perform a reconnect") }
                        ) {
                            NavigationStack {
                                SessionListView(viewModel: list, reachability: reachability,
                                                onSelectDetail: { _ in }, onAddSession: { _ in })
                            }.dsCampNavigationChrome()
                        } settings: {
                            NavigationStack { Text("設定") }
                        }
                        .environment(\.dynamicTypeSize, dynamicSize)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                        .environment(\.colorScheme, .light)
                        try await withOfflineWindow(content: content, size: CGSize(width: width, height: width == 428 ? 926 : 667), category: nativeSize) { window in
                            let image = try run.capture(window: window, name: "initial")
                            try run.write("native-context", offlineNativeContext(window))
                            let views = offlineViews(window)
                            #expect(views.contains { $0 is UITabBar }, "The real AppShell must host an OS tab bar")
                            #expect(window.traitCollection.preferredContentSizeCategory == nativeSize)
                            let elements = offlineAX(window)
                            try run.write("accessibility", ["elements": elements.map { $0.metric(window: window) }])
                            let title = reachability == .unreachableHost ? "Mac に届きません" : "インターネットにつながっていません"
                            let lastFetched = UnreachableViewModel(reachability: reachability, host: "100.64.0.1", lastUpdated: lastFetchedAt, onRetry: {}).lastUpdatedText() ?? "最終取得なし"
                            let subtitle = reachability == .unreachableHost ? "\(lastFetched) · スリープ中か Tailscale 切断" : lastFetched
                            let retryTitle = reconnecting ? "再接続しています…" : "再接続を試す"
                            let expectedLabel = "\(title)。\(subtitle)。\(retryTitle)"
                            let matches = elements.filter {
                                let frame = $0.frame(window: window)
                                return $0.object.accessibilityLabel == expectedLabel
                                    && $0.object.accessibilityTraits.contains(.button)
                                    && offlineFinite(frame) && frame.width > 0 && frame.height > 0
                                    && frame.intersects(window.bounds)
                            }
                            try run.write("selector", ["method": "exact-full-label-and-button-trait-and-finite-visible-frame",
                                "expectedLabel": expectedLabel, "matchingCount": matches.count,
                                "identifierProtocolAvailable": matches.first.map { $0.object is any UIAccessibilityIdentification } ?? false,
                                "observedIdentifier": matches.first?.identifier as Any? ?? NSNull()])
                            try #require(matches.count == 1, "Exactly one actual visible retry button must match the full product label and public button trait")
                            let button = try #require(matches.first)
                            let frame = button.frame(window: window)
                            try run.write("layout", ["window": offlineRect(window.bounds), "button": offlineRect(frame),
                                "nativeCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
                                "reconnecting": reconnecting, "enabledAXTrait": !button.object.accessibilityTraits.contains(.notEnabled)])
                            try #require(offlineFinite(frame), "The actual public AX retry frame is unresolved/nonfinite; inspect PNG, accessibility.json and native-context.json")
                            #expect(frame.width >= 44 && frame.height >= 44)
                            #expect(window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "The actual button frame must fit in the native window")
                            #expect(button.object.accessibilityTraits.contains(.notEnabled) == reconnecting)
                            let crop = frame.intersection(window.bounds)
                            try #require(!crop.isNull && crop.width > 0 && crop.height > 0)
                            let passes = try run.recognize(image: image, crop: crop)
                            var requiredText = [title, "最終取得", reconnecting ? "再接続しています" : "再接続を試す"]
                            if reachability == .unreachableHost { requiredText.append("スリープ中かTailscale切断") }
                            let evaluated = passes.map { pass in
                                let columns = offlineSpatialColumns(pass.lines)
                                let visible = columns.map { offlineNormalize($0.text) }
                                let missing = requiredText.filter { text in !visible.contains { $0.contains(offlineNormalize(text)) } }
                                return (name: pass.name, columns: columns, visible: visible, missing: missing)
                            }
                            try run.write("ocr-columns", ["alignmentTolerance": "half the smaller observed line height",
                                "passes": evaluated.map { pass in
                                    ["name": pass.name, "missingText": pass.missing,
                                     "columns": pass.columns.map { ["text": $0.text, "lineIndices": $0.indices] as [String: Any] }] as [String: Any]
                                }])
                            #expect(evaluated.contains { $0.missing.isEmpty }, "At least one independent OCR pass must strictly recognize every required full text; do not combine characters across passes")
                            let visible = evaluated.flatMap(\.visible)
                            #expect(visible.contains { $0.contains(offlineNormalize(title)) }, "Visible title missing; inspect initial.png and OCR metrics")
                            #expect(visible.contains { $0.contains(offlineNormalize("最終取得")) }, "Visible last-fetch text missing")
                            if reachability == .unreachableHost {
                                #expect(visible.contains { $0.contains(offlineNormalize("スリープ中かTailscale切断")) }, "Visible cause is clipped or not recognized; inspect image")
                            }
                            #expect(visible.contains { $0.contains(offlineNormalize(reconnecting ? "再接続しています" : "再接続を試す")) }, "Visible retry text missing")
                            if #available(iOS 26, *), width == 428, sizeName == "large", reachability == .unreachableHost, !reconnecting {
                                try await run.attemptNativeScroll(window: window)
                            }
                        }
    }
}

struct OfflineScenario: Sendable, CustomStringConvertible {
    let host: Bool
    let sizeIndex: Int
    let width: Int
    let reconnecting: Bool
    var description: String { "\(host ? "host" : "network")-size\(sizeIndex)-\(width)-retry\(reconnecting)" }
    static let all: [Self] = [true, false].flatMap { host in
        [0, 1, 2].flatMap { size in
            [428, 375].flatMap { width in
                [false, true].map { retry in Self(host: host, sizeIndex: size, width: width, reconnecting: retry) }
            }
        }
    }
}

@MainActor
private func withOfflineWindow<Content: View>(content: Content, size: CGSize, category: UIContentSizeCategory,
                                             operation: (UIWindow) async throws -> Void) async throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    window.traitOverrides.preferredContentSizeCategory = category
    let host = UIHostingController(rootView: content)
    host.traitOverrides.preferredContentSizeCategory = category
    window.rootViewController = host
    defer {
        window.isHidden = true
        window.rootViewController = nil
        if let previous, !previous.isHidden { previous.makeKey() }
    }
    window.makeKeyAndVisible()
    try await Task.sleep(for: .milliseconds(700))
    window.layoutIfNeeded()
    try #require(host.view.window === window && host.view.bounds.width == size.width)
    try await operation(window)
}

@MainActor
private func offlineViews(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(offlineViews) }

private func offlineFinite(_ value: CGRect) -> Bool {
    !value.isNull && [value.origin.x, value.origin.y, value.width, value.height].allSatisfy(\.isFinite)
}

/// Hidden/unresolved native AX elements can expose infinity; preserve it without crashing JSONSerialization.
private func offlineRect(_ value: CGRect) -> [String: Any] {
    let components = [value.origin.x, value.origin.y, value.width, value.height]
    return ["xywh": components.map { $0.isFinite ? Double($0) as Any : String(describing: $0) as Any },
            "raw": NSCoder.string(for: value), "finite": offlineFinite(value), "isNull": value.isNull]
}

@MainActor
private func offlineNativeContext(_ window: UIWindow) -> [String: Any] {
    let host = window.rootViewController
    let views = offlineViews(window)
    return ["windowBounds": offlineRect(window.bounds), "windowFrame": offlineRect(window.frame),
            "screenBounds": offlineRect(window.screen.bounds), "windowIsKey": window.isKeyWindow,
            "windowHidden": window.isHidden,
            "windowCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
            "hostCategory": host?.traitCollection.preferredContentSizeCategory.rawValue ?? "missing",
            "hostViewCategory": host?.view.traitCollection.preferredContentSizeCategory.rawValue ?? "missing",
            "globalCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "windowBodyFont": UIFont.preferredFont(forTextStyle: .body, compatibleWith: window.traitCollection).pointSize,
            "globalBodyFont": UIFont.preferredFont(forTextStyle: .body).pointSize,
            "hostBounds": host.map { offlineRect($0.view.bounds) } ?? [:],
            "nativeTabFrames": views.compactMap { $0 as? UITabBar }.map { offlineRect($0.convert($0.bounds, to: window)) },
            "clippingContainers": views.filter { $0.clipsToBounds && !$0.isHidden }.map {
                ["type": String(reflecting: type(of: $0)), "bounds": offlineRect($0.bounds),
                 "frameInWindow": offlineRect($0.convert($0.bounds, to: window)), "alpha": $0.alpha] as [String: Any]
            },
            "hostAttachedToWindow": host?.view.window === window]
}

private func offlineNormalize(_ value: String) -> String {
    value.filter { !$0.isWhitespace && !"…。·.,、".contains($0) }.lowercased()
}

/// Join only lines in the same spatial column. No expected text is used for grouping.
/// Half a glyph-line height allows natural leading/centering variation without joining adjacent columns.
private func offlineSpatialColumns(_ lines: [(text: String, frame: CGRect)]) -> [(text: String, indices: [Int])] {
    lines.map { anchor in
        let indices = lines.indices.filter { index in
            let frame = lines[index].frame
            let tolerance = min(anchor.frame.height, frame.height) / 2
            return abs(anchor.frame.minX - frame.minX) <= tolerance
                || abs(anchor.frame.midX - frame.midX) <= tolerance
        }.sorted { lhs, rhs in
            let left = lines[lhs].frame
            let right = lines[rhs].frame
            return left.minY == right.minY ? left.minX < right.minX : left.minY > right.minY
        }
        return (indices.map { lines[$0].text }.joined(), indices)
    }
}

private func offlineJSONValue(_ value: Any) -> Any {
    if let object = value as? [String: Any] { return object.mapValues(offlineJSONValue) }
    if let array = value as? [Any] { return array.map(offlineJSONValue) }
    if let number = value as? NSNumber, !number.doubleValue.isFinite {
        return ["raw": number.stringValue, "finite": false] as [String: Any]
    }
    return value
}

@MainActor
private struct OfflineAXElement {
    let object: NSObject
    var identifier: String? { (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier }
    func frame(window: UIWindow) -> CGRect { window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace) }
    func metric(window: UIWindow) -> [String: Any] {
        let actualFrame = frame(window: window)
        var metric: [String: Any] = ["label": object.accessibilityLabel ?? "", "identifier": identifier ?? "",
            "frame": offlineRect(actualFrame), "traits": object.accessibilityTraits.rawValue,
            "type": String(reflecting: type(of: object)),
            "frameStatus": offlineFinite(actualFrame) ? "finite-public-frame" : "nonfinite-public-frame-unresolved"]
        if let view = object as? UIView {
            metric["view"] = ["hidden": view.isHidden, "alpha": view.alpha, "attachedToWindow": view.window != nil,
                              "bounds": offlineRect(view.bounds), "frame": offlineRect(view.frame),
                              "nativeCategory": view.traitCollection.preferredContentSizeCategory.rawValue]
        }
        return metric
    }
}

@MainActor
private func offlineAX(_ root: NSObject) -> [OfflineAXElement] {
    var visited: Set<ObjectIdentifier> = []
    var result: [OfflineAXElement] = []
    func inspect(_ object: NSObject) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        if object.isAccessibilityElement { result.append(OfflineAXElement(object: object)) }
        for child in object.accessibilityElements ?? [] { if let child = child as? NSObject { inspect(child) } }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count { if let child = object.accessibilityElement(at: index) as? NSObject { inspect(child) } }
        }
        if let view = object as? UIView { for child in view.subviews { inspect(child) } }
    }
    inspect(root)
    return result
}

@MainActor
private struct OfflineRun {
    let directory: URL
    init(name: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["PHLOX_OFFLINE_OUTPUT"]
            ?? root.appendingPathComponent(".verification/ios-redesign-stage8b/remaining/offline-runtime").path
        try #require(path.hasPrefix("/"))
        directory = URL(fileURLWithPath: path).appendingPathComponent("\(name)-ios\(UIDevice.current.systemVersion)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("owner", ["purpose": "native offline accessory layout", "pid": ProcessInfo.processInfo.processIdentifier,
                            "executable": Bundle.main.executableURL?.path ?? "unknown", "output": directory.path])
        print("offline acceptance output: \(directory.path)")
    }
    func write(_ name: String, _ payload: [String: Any]) throws {
        let safePayload = offlineJSONValue(payload)
        try #require(JSONSerialization.isValidJSONObject(safePayload), "Unsupported metric value; do not invoke JSONSerialization with an invalid object")
        try JSONSerialization.data(withJSONObject: safePayload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    }
    @discardableResult
    func capture(window: UIWindow, name: String) throws -> UIImage {
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(drawn)
        try #require(image.pngData()).write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        return image
    }
    func recognize(image: UIImage, crop: CGRect) throws -> [OfflineOCRPass] {
        let cgImage = try #require(image.cgImage)
        let pixels = CGRect(x: crop.minX * image.scale, y: crop.minY * image.scale,
                            width: crop.width * image.scale, height: crop.height * image.scale)
        let cropped = try #require(cgImage.cropping(to: pixels))
        let grayscale = CIImage(cgImage: cropped).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0, kCIInputContrastKey: 1.5,
        ])
        let contrast = try #require(CIContext().createCGImage(grayscale, from: grayscale.extent))
        return try [("original", cropped), ("grayscale-contrast1.5", contrast)].map { name, input in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            try VNImageRequestHandler(cgImage: input).perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> (text: String, frame: CGRect)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return (text, observation.boundingBox)
            }
            if name == "original" {
                try write("ocr", ["cropInWindow": offlineRect(crop), "lines": lines.map {
                    ["text": $0.text, "normalizedBoundingBox": offlineRect($0.frame)] as [String: Any]
                }])
            }
            try #require(UIImage(cgImage: input).pngData()).write(to: directory.appendingPathComponent("ocr-\(name).png"), options: .atomic)
            try write("ocr-\(name)", ["cropInWindow": offlineRect(crop), "lines": observations.map { observation in
                ["candidates": observation.topCandidates(5).map { ["text": $0.string, "confidence": $0.confidence] as [String: Any] },
                 "normalizedBoundingBox": offlineRect(observation.boundingBox)] as [String: Any]
            }])
            return OfflineOCRPass(name: name, lines: lines)
        }
    }
    func attemptNativeScroll(window: UIWindow) async throws {
        let scrolls = offlineViews(window).compactMap { $0 as? UIScrollView }.filter {
            $0.isScrollEnabled && $0.bounds.height > 0 && $0.contentSize.height > $0.bounds.height
        }
        guard let scroll = scrolls.max(by: { $0.bounds.height < $1.bounds.height }) else {
            try write("scroll", ["status": "blocked", "reason": "No enabled overflowing native UIScrollView was exposed"])
            return
        }
        let before = scroll.contentOffset.y
        let accepted = scroll.accessibilityScroll(.down)
        try await Task.sleep(for: .milliseconds(700))
        let after = scroll.contentOffset.y
        let moved = accepted && after > before + 0.5
        try write("scroll", ["accepted": accepted, "beforeOffsetY": before, "afterOffsetY": after,
            "bounds": offlineRect(scroll.bounds), "contentHeight": scroll.contentSize.height,
            "status": moved ? "moved-review-native-tab-image" : "blocked",
            "reason": moved ? "Public AX accepted and actual offset increased; tab collapse needs visual review"
                : "Public AX scroll was rejected or actual offset did not increase; no direct offset fallback"])
        if moved { try capture(window: window, name: "after-public-ax-scroll") }
    }
}

private struct OfflineOCRPass {
    let name: String
    let lines: [(text: String, frame: CGRect)]
}
