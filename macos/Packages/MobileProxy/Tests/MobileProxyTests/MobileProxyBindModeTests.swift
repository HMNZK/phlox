import Foundation
import Network
import Testing
@testable import MobileProxy

/// バインドモード(露出範囲)の決定ロジックと、fail-closed フォールバックの回帰ガード。
@Suite struct MobileProxyBindModeTests {

    // ---- 決定ロジック(純関数)の単体: 全 IF への暗黙バインドが起きないことを機械的に固定 ----

    // listenHost 明示 → explicitHost(その host)。利用者の意図的選択のみ全 IF/LAN を許す。
    @Test func explicitHostIsHonored() {
        let mode = BindMode.resolve(listenHost: "127.0.0.1") { nil }
        #expect(mode == .explicitHost("127.0.0.1"))
        #expect(mode.bindHost == "127.0.0.1")
    }

    // listenHost 明示で 0.0.0.0 → explicitHost("0.0.0.0")。明示時のみ全 IF を許可。
    @Test func explicitAllInterfacesIsHonoredOnlyWhenExplicit() {
        let mode = BindMode.resolve(listenHost: "0.0.0.0") { nil }
        #expect(mode == .explicitHost("0.0.0.0"))
        #expect(mode.bindHost == "0.0.0.0")
    }

    // listenHost 未指定 + Tailscale 解決成功 → tailscale(特定 IP)。その IP にバインド。
    @Test func tailscaleResolvedBindsToSpecificIP() {
        let mode = BindMode.resolve(listenHost: nil) { "100.64.1.2" }
        #expect(mode == .tailscale("100.64.1.2"))
        #expect(mode.bindHost == "100.64.1.2")
    }

    // ★fail-closed の核心: 未指定 + Tailscale 未解決 → loopbackOnly。
    // 決して 0.0.0.0(全 IF)を返さない。bindHost は 127.0.0.1。
    @Test func tailscaleUnresolvedFallsBackToLoopbackOnlyNeverAllInterfaces() {
        let mode = BindMode.resolve(listenHost: nil) { nil }
        #expect(mode == .loopbackOnly)
        #expect(mode.bindHost == "127.0.0.1")
        // 旧 fail-open(全 IF=0.0.0.0)が再発しないことを明示的に固定する。
        #expect(mode.bindHost != "0.0.0.0")
    }

    // ---- bind プラン(実 bind アドレス + accept 許可 CIDR)の純関数テスト ----

    // tailscale モード: 実 bind は 0.0.0.0(utun 着信を受けるため)。接続元 CIDR は
    // Tailscale 範囲(100.64.0.0/10) + loopback(127.0.0.0/8)。LAN(en0)接続元はこれに入らない。
    @Test func bindPlanForTailscaleBindsAllInterfacesWithTailscaleAndLoopbackCIDRs() {
        let plan = MobileProxy.bindPlan(for: .tailscale("100.64.0.10"))
        #expect(plan.bindAddress == "0.0.0.0")
        #expect(plan.allowedRemoteCIDRs == ["100.64.0.0/10", "127.0.0.0/8"])
        // LAN(en0 相当)接続元は許可 CIDR に入らない。
        #expect(!AcceptFilter.shouldAccept(remoteIP: "172.26.3.4", allowedCIDRs: plan.allowedRemoteCIDRs))
        // iPhone(Tailscale ピア)は入る。
        #expect(AcceptFilter.shouldAccept(remoteIP: "100.64.0.20", allowedCIDRs: plan.allowedRemoteCIDRs))
    }

    // loopbackOnly モード: 実 bind は 127.0.0.1(隔離維持)、許可 CIDR は loopback のみ。
    @Test func bindPlanForLoopbackOnlyBindsLoopbackWithLoopbackCIDROnly() {
        let plan = MobileProxy.bindPlan(for: .loopbackOnly)
        #expect(plan.bindAddress == "127.0.0.1")
        #expect(plan.allowedRemoteCIDRs == ["127.0.0.0/8"])
        // Tailscale ピアは許可されない(隔離)。
        #expect(!AcceptFilter.shouldAccept(remoteIP: "100.64.0.20", allowedCIDRs: plan.allowedRemoteCIDRs))
    }

    // explicitHost(loopback): bind も許可 CIDR も loopback。
    @Test func bindPlanForLoopbackExplicitHostStaysIsolated() {
        let plan = MobileProxy.bindPlan(for: .explicitHost("127.0.0.1"))
        #expect(plan.bindAddress == "127.0.0.1")
        #expect(plan.allowedRemoteCIDRs == ["127.0.0.0/8"])
    }

    // explicitHost(非 loopback): 0.0.0.0 bind + Tailscale 範囲 + loopback CIDR。
    @Test func bindPlanForNonLoopbackExplicitHostBindsAllInterfaces() {
        let plan = MobileProxy.bindPlan(for: .explicitHost("100.64.1.2"))
        #expect(plan.bindAddress == "0.0.0.0")
        #expect(plan.allowedRemoteCIDRs == ["100.64.0.0/10", "127.0.0.0/8"])
    }

    // ---- 実バインド(start)の回帰ガード ----

    /// 生レスポンスを組み立てる小ヘルパ。
    private func okResponse(body: String) -> Data {
        let text = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        return Data(text.utf8)
    }

    // resolver が常に nil(Tailscale 不在) かつ listenHost 未指定で start すると、
    // BindMode == .loopbackOnly になり、loopback(127.0.0.1)経由では中継できるが
    // 全 IF には開かない(=0.0.0.0 バインドが起きていない)ことを実起動で固定する。
    @Test func startWithNoTailscaleBindsLoopbackOnlyAndStillRelays() async throws {
        let response = okResponse(body: "ok")
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        // resolver は常に nil(Tailscale 不在)。listenHost は未指定。
        let proxy = MobileProxy(
            listenHost: nil,
            listenPort: 0,
            targetPort: stubPort,
            resolver: TailscaleIPResolver { _ in
                CommandResult(exitCode: 1, standardOutput: "")
            }
        )
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        // ★fail-closed: 全 IF ではなく loopback 限定にバインドされている。
        #expect(await proxy.bindMode == .loopbackOnly)

        // loopback 経由なら依然として中継できる(機能は維持)。
        let received = try await RawHTTPClient.send(
            Data("GET /sessions HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
            toPort: listenPort,
            host: "127.0.0.1"
        )
        #expect(received == response)
    }

    // listenHost を明示したときは explicitHost になる。
    @Test func startWithExplicitHostReportsExplicitMode() async throws {
        let response = okResponse(body: "x")
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort)
        _ = try await proxy.start()
        defer { Task { await proxy.stop() } }

        #expect(await proxy.bindMode == .explicitHost("127.0.0.1"))
    }

    // half-close: クライアントがリクエスト送信後に送信方向を閉じても応答が欠落しない。
    @Test func halfCloseFromClientStillReceivesResponse() async throws {
        let body = #"{"sessions":[]}"#
        let response = okResponse(body: body)
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort)
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let received = try await RawHTTPClient.sendHalfClosing(
            Data("GET /sessions HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
            toPort: listenPort,
            host: "127.0.0.1"
        )
        #expect(received == response)
        #expect((String(data: received, encoding: .utf8) ?? "").contains(body))
    }
}
