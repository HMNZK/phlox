import Foundation
import Testing
@testable import MobileProxy

@Suite struct TailscaleIPResolverTests {

    // `tailscale ip -4` が IPv4 を返したらそれを採用する。
    @Test func returnsFirstIPv4WhenCommandSucceeds() {
        let resolver = TailscaleIPResolver { _ in
            CommandResult(exitCode: 0, standardOutput: "100.101.102.103\nfd7a::1\n")
        }
        #expect(resolver.resolveIPv4() == "100.101.102.103")
    }

    // コマンドが見つからない(実行不可)ときは nil(=全 IF フォールバック)。
    @Test func returnsNilWhenCommandUnavailable() {
        let resolver = TailscaleIPResolver { _ in
            throw TailscaleIPResolver.CommandError.launchFailed
        }
        #expect(resolver.resolveIPv4() == nil)
    }

    // 非 0 終了(ログイン前など)のときは nil。
    @Test func returnsNilOnNonZeroExit() {
        let resolver = TailscaleIPResolver { _ in
            CommandResult(exitCode: 1, standardOutput: "")
        }
        #expect(resolver.resolveIPv4() == nil)
    }

    // 出力が空・空白のみのときは nil。
    @Test func returnsNilOnBlankOutput() {
        let resolver = TailscaleIPResolver { _ in
            CommandResult(exitCode: 0, standardOutput: "  \n  \n")
        }
        #expect(resolver.resolveIPv4() == nil)
    }

    // 出力に IPv4 らしくない文字列が来たら採用しない(安全側)。
    @Test func rejectsNonIPv4Output() {
        let resolver = TailscaleIPResolver { _ in
            CommandResult(exitCode: 0, standardOutput: "not-an-ip\n")
        }
        #expect(resolver.resolveIPv4() == nil)
    }
}
