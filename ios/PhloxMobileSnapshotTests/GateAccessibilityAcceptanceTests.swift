import SwiftUI
import UIKit
import Vision
import CoreImage
import Testing
import PhloxCore
import DesignSystemIOS
@testable import Features
@testable import PhloxMobile

@MainActor
@Suite(.serialized)
struct GateAccessibilityAcceptanceTests {
    @Test(arguments: [428, 375])
    func failedGateTextIsFullyReachableAtAX5(hostWidth: Int) async throws {
        try #require(UITestingSupport.isEnabled)
        // IOSColor reads ThemeStore, independently of SwiftUI's colorScheme.
        // Override only this test app's in-memory argument domain, never persisted preferences.
        let preferences = UserDefaults.standard
        let fixtureThemeID = AppearancePreference.system.themeID(systemColorScheme: .light)
        let previousArguments = preferences.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixtureArguments = previousArguments
        fixtureArguments[ThemeStore.themeKey] = fixtureThemeID
        preferences.setVolatileDomain(fixtureArguments, forName: UserDefaults.argumentDomain)
        defer { preferences.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        try #require(ThemeStore.active.id == fixtureThemeID && ThemeStore.active.preferredColorScheme == .light,
                     "The white-on-dark Capsule pixel test requires the explicit light product theme")
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: CGFloat(hostWidth), height: hostWidth == 428 ? 926 : 667)
        let model = LaunchGateViewModel(authenticator: StubAuthenticator(allows: false))
        model.state = .failed("認証できませんでした")
        let host = UIHostingController(rootView: LaunchGateView(viewModel: model, onUnlocked: {
            Issue.record("The failed gate rendering test must not authenticate")
        }, automaticallyAuthenticates: false)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.colorScheme, .light))
        window.rootViewController = host
        let run = try GateRun(width: hostWidth)
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            if let previous, !previous.isHidden { previous.makeKey() }
        }
        window.makeKeyAndVisible()
        try await gateDisplayFrames(window)
        var image = try run.capture(window: window, name: "initial")
        _ = try run.recognize(image, crop: window.bounds, name: "initial-full")
        try #require(UIApplication.shared.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge,
                     "Run with the real global AX5 setting; the test does not change OS preferences")
        try #require(window.traitCollection.preferredContentSizeCategory == .accessibilityExtraExtraExtraLarge)
        let targets = [
            ("tagline", "エージェントを止めないリモコン", Optional<String>.none),
            ("heading", "認証できませんでした", Optional<String>.none),
            ("failureBody", "Face ID で本人を確かめられませんでした。もう一度 Face ID を試すか、パスコードで解除してください。", Optional<String>.none),
            ("retry", "もう一度 Face ID", Optional(AccessibilityID.launchGateUnlock)),
            ("footer", "トークンは Keychain に保護されています。認証するまで Mac には接続しません。", Optional<String>.none),
        ]
        for (name, text, identifier) in targets {
            var element = try gateTarget(window, text: text, identifier: identifier)
            var frame = element.map { window.convert($0.accessibilityFrame, from: window.screen.coordinateSpace) } ?? .null
            if !gateVisible(frame, in: window) {
                let scrolls = gateObjects(window).compactMap { $0 as? UIScrollView }.filter {
                    $0.isScrollEnabled && $0.bounds.height > 0
                        && $0.contentSize.height + $0.adjustedContentInset.top + $0.adjustedContentInset.bottom > $0.bounds.height + 1
                }
                let scroll = try #require(scrolls.max { $0.bounds.height < $1.bounds.height },
                                          "Offscreen \(name) requires a real enabled overflowing ScrollView")
                try await run.reveal(window: window, scroll: scroll, target: name, text: text)
                element = try gateTarget(window, text: text, identifier: identifier)
                frame = element.map { window.convert($0.accessibilityFrame, from: window.screen.coordinateSpace) } ?? .null
                image = try run.capture(window: window, name: "revealed-\(name)")
            }
            try run.write("\(name)-frame", ["text": text, "frame": gateRect(frame), "fullyVisible": gateVisible(frame, in: window)])
            try #require(gateVisible(frame, in: window), "The actual \(name) frame must be fully visible before OCR")
            let visible = try run.recognize(image, crop: frame.insetBy(dx: -2, dy: -2).intersection(window.bounds), name: name)
            #expect(visible.contains { gateNormalize($0).contains(gateNormalize(text)) }, "Visible \(name) is incomplete; inspect saved PNG and raw OCR")
            if name == "retry" {
                #expect(frame.width >= 44 && frame.height >= 44)
                try run.verifyCapsuleForeground(image, frame: frame)
            }
        }
    }
}

/// Light-mode contract: pure-white foreground must stay inside the dark Capsule.
private func gateCapsulePixels(_ image: CGImage, scale: CGFloat, crop: CGRect, capsule: CGRect) throws
    -> (white: Int, outside: Int, samples: [[Double]]) {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "GateCapsulePixels", code: 1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let radius = min(capsule.width, capsule.height) / 2
    var white = 0
    var outside = 0
    var samples: [[Double]] = []
    for y in 0..<image.height {
        for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            guard pixels[index..<(index + 4)].allSatisfy({ $0 >= 250 }) else { continue }
            white += 1
            let point = CGPoint(x: crop.minX + (CGFloat(x) + 0.5) / scale,
                                y: crop.minY + (CGFloat(y) + 0.5) / scale)
            let center = CGPoint(x: min(max(point.x, capsule.minX + radius), capsule.maxX - radius),
                                 y: min(max(point.y, capsule.minY + radius), capsule.maxY - radius))
            let dx = point.x - center.x, dy = point.y - center.y
            // One point tolerates raster edge antialiasing; no per-image geometry is fitted.
            if dx * dx + dy * dy > (radius + 1) * (radius + 1) {
                outside += 1
                if samples.count < 10 { samples.append([Double(point.x), Double(point.y)]) }
            }
        }
    }
    return (white, outside, samples)
}

private func gateNormalize(_ text: String) -> String { text.filter { !$0.isWhitespace } }
private func gateRect(_ frame: CGRect) -> [String: Any] {
    ["raw": NSCoder.string(for: frame), "finite": !frame.isNull && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
     "xywh": [frame.minX, frame.minY, frame.width, frame.height].map {
        $0.isFinite ? Double($0) as Any : String(describing: $0) as Any
    }]
}

@MainActor
private func gateVisible(_ frame: CGRect, in window: UIWindow) -> Bool {
    [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
        && frame.width > 0 && frame.height > 0 && window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame)
}

@MainActor
private func gateObjects(_ root: NSObject) -> [NSObject] {
    var result: [NSObject] = []
    var seen: Set<ObjectIdentifier> = []
    func visit(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted else { return }
        result.append(object)
        for child in object.accessibilityElements ?? [] {
            if let child = child as? NSObject { visit(child) }
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound && count > 0 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject { visit(child) }
            }
        }
        if let view = object as? UIView {
            for child in view.subviews { visit(child) }
        }
    }
    visit(root)
    return result
}

@MainActor
private func gateTarget(_ window: UIWindow, text: String, identifier: String?) throws -> NSObject? {
    let objects = gateObjects(window)
    let identified = identifier.map { identifier in
        objects.filter { ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier == identifier }
    } ?? []
    let candidates = identified.isEmpty ? objects.filter {
        $0.accessibilityLabel.map { gateNormalize($0) == gateNormalize(text) } ?? false
    } : identified
    let matches = candidates.filter { object in
        let frame = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace)
        return !frame.isNull && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
            && (identifier == nil || object.accessibilityTraits.contains(.button))
    }
    try #require(matches.count <= 1, "Actual public AX target must be unique: \(text)")
    return matches.first
}

@MainActor
private struct GateRun {
    let directory: URL
    init(width: Int) throws {
        let variables = ProcessInfo.processInfo.environment
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let base = variables["PHLOX_REMAINING_OUTPUT"] ?? variables["TEST_RUNNER_PHLOX_REMAINING_OUTPUT"]
            ?? project.appendingPathComponent(".verification/ios-redesign-stage8b/remaining/gate").path
        directory = URL(fileURLWithPath: base).appendingPathComponent("GateFailedAX5-host\(width)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func write(_ name: String, _ values: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    }
    func capture(window: UIWindow, name: String) throws -> UIImage {
        let objects = gateObjects(window)
        try write("\(name)-context", [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "udid": ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown",
            "window": gateRect(window.bounds), "screen": gateRect(window.screen.bounds),
            "safeArea": [window.safeAreaInsets.top, window.safeAreaInsets.left, window.safeAreaInsets.bottom, window.safeAreaInsets.right],
            "hostViewportIsPhysicalScreen": window.bounds.size == window.screen.bounds.size,
            "globalCategory": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "windowCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
            "ax": objects.map { ["type": String(reflecting: type(of: $0)), "label": $0.accessibilityLabel ?? "",
                "identifier": ($0 as? any UIAccessibilityIdentification)?.accessibilityIdentifier ?? "",
                "traits": $0.accessibilityTraits.rawValue,
                "frame": gateRect(window.convert($0.accessibilityFrame, from: window.screen.coordinateSpace))] as [String: Any] },
            "uiLabelFonts": objects.compactMap { $0 as? UILabel }.map { ["text": $0.text ?? "", "font": $0.font.fontName,
                "pointSize": $0.font.pointSize, "lines": $0.numberOfLines] as [String: Any] },
            "preferredFontMetricsNotRenderedTextMeasurements": [UIFont.TextStyle.headline, .subheadline, .footnote, .caption1].map {
                ["style": $0.rawValue, "pointSize": UIFont.preferredFont(forTextStyle: $0, compatibleWith: window.traitCollection).pointSize] as [String: Any]
            },
        ])
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        try #require(drawn, "Real window drawHierarchy must succeed")
        return image
    }
    func recognize(_ image: UIImage, crop: CGRect, name: String) throws -> [String] {
        let cg = try #require(image.cgImage)
        let pixels = CGRect(x: crop.minX * image.scale, y: crop.minY * image.scale,
                            width: crop.width * image.scale, height: crop.height * image.scale)
        let cropped = try #require(cg.cropping(to: pixels))
        let grayscale = CIImage(cgImage: cropped).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0, kCIInputContrastKey: 1.5,
        ])
        let enhanced = try #require(CIContext().createCGImage(grayscale, from: grayscale.extent))
        // Each complete candidate comes from one pass; never combine characters across passes.
        return try [("original", cropped), ("grayscale-contrast1.5", enhanced)].map { variant, input in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: input, options: [:]).perform([request])
            let observations = (request.results ?? []).sorted {
                abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                    ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
            }
            let visible = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
            let recordName = variant == "original" ? "\(name)-ocr" : "\(name)-\(variant)-ocr"
            try write(recordName, ["variant": variant, "crop": gateRect(crop), "visible": visible,
                                  "lines": observations.map {
                ["candidates": $0.topCandidates(5).map { ["text": $0.string, "confidence": $0.confidence] as [String: Any] },
                 "box": gateRect($0.boundingBox)] as [String: Any]
            }])
            try #require(UIImage(cgImage: input).pngData())
                .write(to: directory.appendingPathComponent("\(name)-\(variant)-crop.png"), options: .atomic)
            return visible
        }
    }
    func verifyCapsuleForeground(_ image: UIImage, frame: CGRect) throws {
        let crop = frame.insetBy(dx: -2, dy: -2).intersection(CGRect(origin: .zero, size: image.size))
        let cg = try #require(image.cgImage)
        let pixels = CGRect(x: crop.minX * image.scale, y: crop.minY * image.scale,
                            width: crop.width * image.scale, height: crop.height * image.scale)
        let cropped = try #require(cg.cropping(to: pixels))
        let metrics = try gateCapsulePixels(cropped, scale: image.scale, crop: crop, capsule: frame)
        try write("retry-capsule-pixels", ["capsule": gateRect(frame), "crop": gateRect(crop),
            "edgeTolerancePoints": 1, "nearWhiteMinimumRGBA": 250, "whitePixels": metrics.white,
            "outsideWhitePixels": metrics.outside, "outsideSamplesInWindow": metrics.samples])
        #expect(metrics.white > 0, "The retry screenshot must contain its real white foreground")
        #expect(metrics.outside == 0, "Strong white foreground must stay within the retry Capsule plus 1pt raster tolerance")
    }
    func reveal(window: UIWindow, scroll: UIScrollView, target: String, text: String) async throws {
        let variables = ProcessInfo.processInfo.environment
        try #require(variables["PHLOX_GATE_INTERACTIVE"] == "1" || variables["TEST_RUNNER_PHLOX_GATE_INTERACTIVE"] == "1",
                     "Offscreen content requires explicitly coordinated real CUA scrolling")
        let nonce = UUID().uuidString
        let ack = directory.appendingPathComponent("\(target)-\(nonce)-ack.json")
        let ready = directory.appendingPathComponent("ready.json")
        let before = scroll.contentOffset.y
        let scene = "GateFailedAX5-host\(Int(window.bounds.width))"
        let pid = ProcessInfo.processInfo.processIdentifier
        let udid = variables["SIMULATOR_UDID"] ?? "unknown"
        let requestedAt = Date().timeIntervalSince1970
        _ = try capture(window: window, name: "awaiting-\(target)")
        try write("ready", ["scene": scene, "step": target, "phase": "awaitingCUA", "text": text, "nonce": nonce,
            "pid": pid, "udid": udid, "requestedAt": requestedAt,
            "ackFile": ack.path, "screenshotFile": directory.appendingPathComponent("awaiting-\(target).png").path,
            "window": gateRect(window.bounds), "scrollViewport": gateRect(scroll.convert(scroll.bounds, to: window)),
            "offsetBefore": before,
            "deadlineEpoch": Date().addingTimeInterval(180).timeIntervalSince1970,
            "instruction": "本物の画面を公開スクロールで操作し、対象全文を表示。任意offset書込禁止。"])
        FileHandle.standardError.write(Data("gate external ready: \(ready.path)\n".utf8))
        let deadline = ContinuousClock.now + .seconds(180)
        while ContinuousClock.now < deadline {
            if let data = try? Data(contentsOf: ack),
               let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                try #require(value["nonce"] as? String == nonce && value["scene"] as? String == scene && value["step"] as? String == target)
                try #require((value["pid"] as? NSNumber)?.int32Value == pid && value["udid"] as? String == udid)
                try #require(value["phase"] as? String == "reviewed" && value["confirmed"] as? Bool == true)
                let capturedAt = try #require(value["capturedAt"] as? Double)
                try #require(capturedAt >= requestedAt && capturedAt <= Date().timeIntervalSince1970 + 5)
                try write("\(target)-reviewed", value)
                try await gateDisplayFrames(window)
                try write("\(target)-scroll-result", ["offsetBefore": before, "offsetAfter": scroll.contentOffset.y, "nonce": nonce])
                try #require(abs(scroll.contentOffset.y - before) > 0.5, "Real scrolling must move the actual content")
                try write("ready", ["phase": "completed-\(target)", "nonce": nonce])
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw GateAcceptanceError.externalScrollTimeout
    }
}

private enum GateAcceptanceError: Error { case externalScrollTimeout, displayFramesTimeout }

@MainActor
private func gateDisplayFrames(_ window: UIWindow) async throws {
    let frames = GateDisplayFrames()
    let link = CADisplayLink(target: frames, selector: #selector(GateDisplayFrames.tick))
    link.add(to: .main, forMode: .common)
    defer { link.invalidate() }
    window.setNeedsLayout()
    window.layoutIfNeeded()
    CATransaction.flush()
    let deadline = ContinuousClock.now + .seconds(5)
    while frames.count < 3 {
        guard ContinuousClock.now < deadline else { throw GateAcceptanceError.displayFramesTimeout }
        try await Task.sleep(for: .milliseconds(30))
    }
    window.layoutIfNeeded()
    CATransaction.flush()
}

@MainActor
private final class GateDisplayFrames: NSObject {
    var count = 0
    @objc func tick() { count += 1 }
}
