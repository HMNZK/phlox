import AppKit
import CryptoKit
import Foundation
import SwiftTerm
import Testing
@testable import TerminalUI

@MainActor
@Suite(.serialized)
struct TerminalRuntimeImageStoreTests {
    private final class WeakSource {
        weak var value: NSObject?
        init(_ value: NSObject?) { self.value = value }
    }

    private func directory() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent(".verification/runtime-terminal-projection/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try "TerminalUI画像共有検証用。起動プロセスなし。実行終了後にゴミ箱へ移動。".write(
            to: directory.appendingPathComponent("ownership.md"), atomically: true, encoding: .utf8)
        return directory
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = try directory()
        defer {
            do { try FileManager.default.trashItem(at: directory, resultingItemURL: nil) }
            catch { Issue.record(error, "今回の画像検証fixtureをゴミ箱へ移動できなかった") }
        }
        try body(directory.appendingPathComponent("images"))
    }

    @Test("内容が同じ画像を再保存せず既存snapshotの画像も読める")
    func immutableContentReferences() throws {
        try withDirectory { directory in
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true)
            let source = NSObject()
            let original = Data("original".utf8)
            let contentID = try writer.reference(source: source) { original }
            for _ in 0..<10 {
                #expect(try writer.reference(source: source) { Issue.record("同じ画像を再符号化した"); return Data() } == contentID)
            }
            _ = try writer.reference(source: NSObject()) { Data("next".utf8) }
            let reader = try TerminalRuntimeImageStore(directory: directory, writable: false)
            #expect(try reader.read(contentID) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
        }
    }

    @Test("使われなくなった画像も応答期限内は読め、期限後に容量を再利用できる")
    func reclaimExpiredImageCapacity() throws {
        try withDirectory { directory in
            let start = ContinuousClock.now
            var elapsed = Duration.zero
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true,
                capacityBytes: 8, now: { start.advanced(by: elapsed) })
            var oldSource: NSObject? = NSObject()
            let oldSourceWeak = WeakSource(oldSource)
            let oldID = try writer.reference(source: try #require(oldSource)) { Data("old!".utf8) }
            let reader = try TerminalRuntimeImageStore(directory: directory, writable: false)
            oldSource = nil
            #expect(oldSourceWeak.value == nil)
            try writer.collectGarbage()
            elapsed = .seconds(39)
            try writer.collectGarbage()
            #expect(try reader.read(oldID) == Data("old!".utf8))
            #expect(throws: (any Error).self) {
                try writer.reference(source: NSObject()) { Data("new!!".utf8) }
            }
            elapsed = .seconds(41)
            let newID = try writer.reference(source: NSObject()) { Data("new!!".utf8) }
            #expect(try reader.read(newID) == Data("new!!".utf8))
            #expect(throws: TerminalRuntimeImageError.staleReference(contentID: oldID)) {
                try reader.read(oldID)
            }
        }
    }

    @Test("同じ画像を別の生きたsourceが共有していれば最初のsource死亡後も回収しない")
    func retainSharedLiveImage() throws {
        try withDirectory { directory in
            let start = ContinuousClock.now
            var elapsed = Duration.zero
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true,
                capacityBytes: 8, now: { start.advanced(by: elapsed) })
            var first: NSObject? = NSObject()
            let contentID = try writer.reference(source: try #require(first)) { Data("same".utf8) }
            let second = NSObject()
            defer { withExtendedLifetime(second) {} }
            #expect(try writer.reference(source: second) { Data("same".utf8) } == contentID)
            first = nil
            try writer.collectGarbage()
            elapsed = .seconds(80)
            try writer.collectGarbage()
            #expect(try writer.read(contentID) == Data("same".utf8))
            #expect(throws: (any Error).self) {
                try writer.reference(source: NSObject()) { Data("other".utf8) }
            }
        }
    }

    @Test("再起動前に保存された画像も期限後に回収する")
    func reclaimPreviousRuntimeImages() throws {
        try withDirectory { directory in
            let start = ContinuousClock.now
            var elapsed = Duration.zero
            do {
                let previous = try TerminalRuntimeImageStore(directory: directory, writable: true, capacityBytes: 8)
                _ = try previous.reference(source: NSObject()) { Data("past".utf8) }
            }
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true,
                capacityBytes: 8, now: { start.advanced(by: elapsed) })
            elapsed = .seconds(41)
            let id = try writer.reference(source: NSObject()) { Data("fresh".utf8) }
            #expect(try writer.read(id) == Data("fresh".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
        }
    }

    @Test("パス差替え・symbolic link・改ざん画像を拒否する")
    func rejectUnsafeFiles() throws {
        try withDirectory { directory in
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true)
            let contentID = try writer.reference(source: NSObject()) { Data("original".utf8) }
            let reader = try TerminalRuntimeImageStore(directory: directory, writable: false)
            #expect(throws: (any Error).self) { try reader.read("../outside") }
            let file = directory.appendingPathComponent(contentID)
            try Data("changed".utf8).write(to: file)
            #expect(throws: (any Error).self) { try reader.read(contentID) }
            let linkedID = String(repeating: "a", count: 64)
            try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent(linkedID).path,
                withDestinationPath: file.path)
            #expect(throws: (any Error).self) { try reader.read(linkedID) }
        }
    }

    @Test("inline画像を再接続で復元し画像の読取失敗時は表示を変更しない")
    func restoreInlineImage() throws {
        _ = NSApplication.shared
        try withDirectory { directory in
            try TerminalCoordinator.configureRuntimeImageStore(directory: directory, writable: true)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let runtime = TerminalCoordinator()
            runtime.feed(Data("before\r\n".utf8))
            runtime.terminalView.createImage(source: runtime.terminalView.getTerminal(), data: png,
                width: .cells(2), height: .cells(1), preserveAspectRatio: false)
            let snapshot = try runtime.makeRuntimeDisplaySnapshot()
            #expect(!snapshot.lines.flatMap(\.images).isEmpty)
            let gui = try TerminalCoordinator(runtimeProjection: snapshot)
            #expect(gui.terminalView.getTerminal().buffer.hasAnyImages)
            let before = gui.visibleText()
            let image = try #require(snapshot.lines.flatMap(\.images).first)
            try Data("corrupt".utf8).write(to: directory.appendingPathComponent(image.contentID))
            #expect(throws: (any Error).self) { try gui.applyRuntimeDisplaySnapshot(snapshot) }
            #expect(gui.visibleText() == before)
        }
    }

    @Test("Kittyの仮想画像配置も再接続で保持する")
    func restoreVirtualKittyImage() throws {
        try withDirectory { directory in
            try TerminalCoordinator.configureRuntimeImageStore(directory: directory, writable: true)
            let runtime = TerminalCoordinator()
            let rgb = Data([255, 0, 0]).base64EncodedString()
            runtime.feed(Data("\u{1b}_Ga=T,f=24,s=1,v=1,t=d,c=1,r=1,i=1,U=1;\(rgb)\u{1b}\\".utf8))
            runtime.feed(Data("\u{1b}[38;2;0;0;1m\u{10EEEE}\u{0305}\u{0305}".utf8))
            let snapshot = try runtime.makeRuntimeDisplaySnapshot()
            #expect(snapshot.virtualPlacements.count == 1)
            #expect(snapshot.virtualImageContents[1] != nil)
            let gui = try TerminalCoordinator(runtimeProjection: snapshot)
            let restored = try gui.makeRuntimeDisplaySnapshot()
            #expect(restored.virtualPlacements == snapshot.virtualPlacements)
            #expect(Set(restored.virtualImageContents.keys) == Set(snapshot.virtualImageContents.keys))
        }
    }

    @Test("virtual画像の置換で容量不足になっても旧sourceを解放し期限後に復旧する")
    func recoverVirtualSnapshotAfterCapacityFailure() throws {
        try withDirectory { directory in
            let start = ContinuousClock.now
            var elapsed = Duration.zero
            @MainActor func put(_ runtime: TerminalCoordinator, id: Int, rgb: [UInt8]) {
                let payload = Data(rgb).base64EncodedString()
                runtime.feed(Data("\u{1b}_Ga=T,f=24,s=1,v=1,t=d,c=1,r=1,i=\(id),U=1;\(payload)\u{1b}\\".utf8))
            }
            let runtime = TerminalCoordinator()
            let probe = TerminalCoordinator()
            put(runtime, id: 1, rgb: [255, 0, 0])
            put(probe, id: 2, rgb: [0, 0, 255])
            var capacity = 0
            for terminal in [runtime, probe] {
                _ = try terminal.terminalView.makeRuntimeDisplaySnapshot { _, encode in
                    capacity = max(capacity, try encode().count)
                    return String(repeating: "a", count: 64)
                }
            }
            let writer = try TerminalRuntimeImageStore(directory: directory, writable: true,
                capacityBytes: capacity, now: { start.advanced(by: elapsed) })
            weak var originalSource: AnyObject?
            let original = try runtime.terminalView.makeRuntimeDisplaySnapshot { source, encode in
                originalSource = source
                return try writer.reference(source: source, encode: encode)
            }
            let originalID = try #require(original.virtualImageContents[1])
            #expect(originalSource != nil)
            runtime.feed(Data("\u{1b}_Ga=d,d=I,i=1;\u{1b}\\".utf8))
            put(runtime, id: 2, rgb: [0, 0, 255])
            #expect(throws: (any Error).self) {
                try runtime.terminalView.makeRuntimeDisplaySnapshot { source, encode in
                    try writer.reference(source: source, encode: encode)
                }
            }
            #expect(originalSource == nil)
            elapsed = .seconds(39)
            try writer.collectGarbage()
            #expect(!(try writer.read(originalID)).isEmpty)
            elapsed = .seconds(41)
            let replacement = try runtime.terminalView.makeRuntimeDisplaySnapshot { source, encode in
                try writer.reference(source: source, encode: encode)
            }
            #expect(Set(replacement.virtualImageContents.keys) == [UInt32(2)])
            let replacementID = try #require(replacement.virtualImageContents[2])
            #expect(!(try writer.read(replacementID)).isEmpty)
            #expect(throws: TerminalRuntimeImageError.staleReference(contentID: originalID)) {
                try writer.read(originalID)
            }
        }
    }
}
