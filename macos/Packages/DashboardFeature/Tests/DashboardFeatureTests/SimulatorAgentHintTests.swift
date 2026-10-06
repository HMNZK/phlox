import Testing
@testable import DashboardFeature

struct SimulatorAgentHintTests {
    @Test func 端末名とiOSの版とUDIDを1行で伝え状態は入れない() {
        let device = SimulatorDevice(udid: "6F1C-42", name: "iPhone 17 Pro",
                                     runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", state: "Shutdown")
        #expect(device.agentHint == "対象の iOS シミュレーター: iPhone 17 Pro（iOS 26.2、UDID 6F1C-42）。Phlox で表示中の端末です。")
    }

    @Test func 端末名の改行や制御文字を除き1行に保つ() {
        let device = SimulatorDevice(udid: "U", name: "my\nphone\r\u{7}",
                                     runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2", state: "Booted")
        #expect(device.agentHint == "対象の iOS シミュレーター: myphone（iOS 26.2、UDID U）。Phlox で表示中の端末です。")
    }
}
