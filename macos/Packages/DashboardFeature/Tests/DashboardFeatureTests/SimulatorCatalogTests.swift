import Foundation
import Testing
@testable import DashboardFeature

struct SimulatorCatalogTests {
    @Test(arguments: ["xcrun: error: unable to find utility \"simctl\", not a developer tool or in PATH",
                      "tool 'simctl' requires Xcode", "invalid active developer path"])
    func Xcodeが見つからない理由を明示する(message: String) async {
        let catalog = SimulatorCatalog { _, _ in
            .init(status: 72, output: Data(), errorOutput: Data(message.utf8))
        }
        let listing = await catalog.list()
        #expect(listing.devices.isEmpty)
        #expect(listing.reason?.hasPrefix("Xcode が見つかりません") == true)
        #expect(listing.reason?.contains(message) == true)
        #expect(listing.reason?.contains("72") == true)
    }

    @Test func 存在しない端末への大きな貼り付けは終了コードと標準エラーを返す() async {
        let udid = "00000000-0000-0000-0000-000000000000"
        do {
            try await SimulatorCatalog().copyPasteboard(udid: udid, text: String(repeating: "a", count: 1_048_576))
            Issue.record("存在しない端末への貼り付けが成功しました")
        } catch SimulatorCatalog.CommandError.failed(let status, let message) {
            #expect(status != 0)
            #expect(message.contains("Invalid device"))
            #expect(message.contains(udid))
        } catch {
            Issue.record("simctlのエラーを失いました: \(error)")
        }
    }
    @Test func 利用可能なiOS端末だけを起動中から並べる() throws {
        let listing = SimulatorCatalog.parse(try fixture())
        #expect(listing.reason == nil)
        #expect(listing.devices.map(\.name) == ["iPad Pro", "iPhone 17 (SB uitest 1)", "iPhone 16", "iPhone 17", "iPhone 17"])
        #expect(listing.devices.map(\.isBooted) == [true, true, false, false, false])
        #expect(listing.devices[2].state == "Booting")
        #expect(listing.devices[3].runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-18-5")
        #expect(listing.devices[4].udid == "1BDE7133-58B4-4D8E-BC69-C653794FACD6")
        #expect(listing.devices[4].id == listing.devices[4].udid)
    }

    @Test func 一覧が空でも理由をエラー扱いしない() {
        #expect(SimulatorCatalog.parse(Data(#"{"devices":{}}"#.utf8)) == .init(devices: [], reason: nil))
    }

    @Test(arguments: ["壊れたJSON", "{}", #"{"devices":[]}"#,
                      #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"iPhone"}]}}"#])
    func 壊れたJSONは空一覧と理由を返す(json: String) {
        let listing = SimulatorCatalog.parse(Data(json.utf8))
        #expect(listing.devices.isEmpty)
        #expect(listing.reason?.hasPrefix("端末一覧のJSONを解析できません:") == true)
    }

    @Test func 同名端末もUDIDで安定して並べる() {
        let data = Data(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"B","name":"iPhone","state":"Shutdown","isAvailable":true},{"udid":"A","name":"iPhone","state":"Shutdown","isAvailable":true}]}}"#.utf8)
        #expect(SimulatorCatalog.parse(data).devices.map(\.udid) == ["A", "B"])
    }

    @Test func 一覧取得は固定JSONだけで検査する() async throws {
        let data = try fixture()
        let catalog = SimulatorCatalog { arguments, input in
            #expect(arguments == ["list", "-j", "devices"])
            #expect(input == nil)
            return .init(status: 0, output: data, errorOutput: Data())
        }
        #expect(await catalog.list() == SimulatorCatalog.parse(data))
    }

    @Test func コマンド失敗は空一覧と終了コードと理由を返す() async {
        let catalog = SimulatorCatalog { _, _ in
            .init(status: 72, output: Data(), errorOutput: Data("Xcodeがありません".utf8))
        }
        let listing = await catalog.list()
        #expect(listing.devices.isEmpty)
        #expect(listing.reason?.contains("72") == true)
        #expect(listing.reason?.contains("Xcodeがありません") == true)
    }

    @Test func 起動失敗の理由を返す() async {
        let catalog = SimulatorCatalog { _, _ in
            throw CocoaError(.executableNotLoadable)
        }
        let listing = await catalog.list()
        #expect(listing.devices.isEmpty)
        #expect(listing.reason?.hasPrefix("端末一覧を取得できません:") == true)
    }

    @Test func 端末操作の引数と貼り付けのUTF8を検査する() async throws {
        let boot = SimulatorCatalog { arguments, input in
            #expect(arguments == ["boot", "端末"])
            #expect(input == nil)
            return .init(status: 0, output: Data(), errorOutput: Data())
        }
        try await boot.boot(udid: "端末")
        let shutdown = SimulatorCatalog { arguments, _ in
            #expect(arguments == ["shutdown", "端末"])
            return .init(status: 0, output: Data(), errorOutput: Data())
        }
        try await shutdown.shutdown(udid: "端末")
        let screenshot = SimulatorCatalog { arguments, _ in
            #expect(arguments == ["io", "端末", "screenshot", "/画像 保存.png"])
            return .init(status: 0, output: Data(), errorOutput: Data())
        }
        try await screenshot.screenshot(udid: "端末", destination: URL(fileURLWithPath: "/画像 保存.png"))
        let pasteboard = SimulatorCatalog { arguments, input in
            #expect(arguments == ["pbcopy", "端末"])
            #expect(input == Data("日本語\n⌘V".utf8))
            return .init(status: 0, output: Data(), errorOutput: Data())
        }
        try await pasteboard.copyPasteboard(udid: "端末", text: "日本語\n⌘V")
    }

    @Test func コピー失敗を成功として返さない() async {
        let catalog = SimulatorCatalog { _, _ in
            .init(status: 1, output: Data("コピーできません".utf8), errorOutput: Data())
        }
        do {
            try await catalog.copyPasteboard(udid: "端末", text: "文字")
            Issue.record("コピー失敗が呼び出し元へ返りませんでした")
        } catch {
            #expect(error.localizedDescription.contains("コピーできません"))
        }
    }

    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "simulator-devices", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
