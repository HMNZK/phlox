import Foundation
import Testing
@testable import MobileProxy

/// accept 時の「接続元(remote peer)IP の CIDR フィルタ」(純関数)のテスト。
///
/// 実機データで getsockname(ローカル宛先)は iPhone も Mac 自身も同一 IP になり判定に使えず、
/// 差が出るのは getpeername(接続元)であることが判明した。Tailscale ピアは必ず 100.64.0.0/10
/// (CGNAT 範囲)なので、接続元 IP が許可 CIDR(Tailscale 範囲 + loopback)に入るかで判定する。
@Suite struct AcceptFilterTests {

    private let allowed = ["100.64.0.0/10", "127.0.0.0/8"]

    // iPhone(Tailscale ピア)= 100.64.0.20 → 100.64.0.0/10 内 → allow。
    @Test func acceptsTailscalePeerIPhone() {
        #expect(AcceptFilter.shouldAccept(remoteIP: "100.64.0.20", allowedCIDRs: allowed))
    }

    // Mac 自身 hairpin = 100.64.0.10 → 範囲内 → allow。
    @Test func acceptsTailscaleHairpinMac() {
        #expect(AcceptFilter.shouldAccept(remoteIP: "100.64.0.10", allowedCIDRs: allowed))
    }

    // 100.64.0.1(範囲の下端)→ allow。
    @Test func acceptsLowerBoundOfTailscaleRange() {
        #expect(AcceptFilter.shouldAccept(remoteIP: "100.64.0.1", allowedCIDRs: allowed))
    }

    // 100.128.0.1 は 100.64.0.0/10 の範囲外(/10 の上端は 100.127.255.255)→ reject。
    @Test func rejectsJustAboveTailscaleRange() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "100.128.0.1", allowedCIDRs: allowed))
    }

    // LAN(en0 相当) 172.26.3.4 → reject。
    @Test func rejectsLAN172() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "172.26.3.4", allowedCIDRs: allowed))
    }

    // LAN 192.168.1.5 → reject。
    @Test func rejectsLAN192() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "192.168.1.5", allowedCIDRs: allowed))
    }

    // 10.0.0.1 → reject。
    @Test func rejectsPrivate10() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "10.0.0.1", allowedCIDRs: allowed))
    }

    // loopback 127.0.0.1 → allow(結合テストの 127.0.0.1 接続元を通すため)。
    @Test func acceptsLoopback() {
        #expect(AcceptFilter.shouldAccept(remoteIP: "127.0.0.1", allowedCIDRs: allowed))
    }

    // グローバル 8.8.8.8 → reject。
    @Test func rejectsGlobal() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "8.8.8.8", allowedCIDRs: allowed))
    }

    // 不正文字列 → reject(安全側)。
    @Test func rejectsMalformed() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "not-an-ip", allowedCIDRs: allowed))
        #expect(!AcceptFilter.shouldAccept(remoteIP: "999.1.1.1", allowedCIDRs: allowed))
        #expect(!AcceptFilter.shouldAccept(remoteIP: "100.64.0", allowedCIDRs: allowed))
    }

    // nil(取得不能)→ reject。
    @Test func rejectsNil() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: nil, allowedCIDRs: allowed))
    }

    // 許可 CIDR が空 → 何も許可しない(fail-closed)。
    @Test func rejectsWhenAllowSetEmpty() {
        #expect(!AcceptFilter.shouldAccept(remoteIP: "100.64.0.20", allowedCIDRs: []))
    }

    // loopback のみの許可集合では Tailscale ピアは拒否される。
    @Test func loopbackOnlyCIDRsRejectTailscalePeer() {
        #expect(AcceptFilter.shouldAccept(remoteIP: "127.0.0.1", allowedCIDRs: ["127.0.0.0/8"]))
        #expect(!AcceptFilter.shouldAccept(remoteIP: "100.64.0.20", allowedCIDRs: ["127.0.0.0/8"]))
    }
}
