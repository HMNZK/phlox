import Testing
@testable import PhloxNetworking

struct HostTrustPolicyTests {
    @Test("IPv4 は4個の10進オクテットだけを受理する")
    func requiresStrictDecimalIPv4() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "100.064.0.1"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "10.0.0"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "10.0.0.1.2"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "10.0.0.256"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "10.0.0.-1"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "10.0.0.a"))
    }

    @Test("100.64.0.0/10 のビット境界を判定する")
    func checksCGNATBitBoundaries() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "100.63.255.255"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "100.64.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "100.127.255.255"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "100.128.0.0"))
    }

    @Test("172.16.0.0/12 のビット境界を判定する")
    func checksPrivate172BitBoundaries() {
        #expect(!HostTrustPolicy.allowsAuthorization(host: "172.15.255.255"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "172.16.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "172.31.255.255"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "172.32.0.0"))
    }

    @Test("他の許可 IPv4 レンジの境界を判定する")
    func checksOtherAllowedIPv4Boundaries() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "10.0.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "10.255.255.255"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "192.168.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "192.168.255.255"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "127.0.0.0"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "127.255.255.255"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "126.255.255.255"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "128.0.0.0"))
    }

    @Test("MagicDNS は大文字小文字を無視しドット境界を要求する")
    func checksMagicDNSLabelBoundaryCaseInsensitively() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "x.ts.net"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "X.TS.NET"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "evil-ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: ".ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "x..ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "..ts.net"))
        #expect(!HostTrustPolicy.allowsAuthorization(host: "x.ts.net.evil"))
    }

    @Test("localhost は大文字小文字を区別しない")
    func allowsLocalhostCaseInsensitively() {
        #expect(HostTrustPolicy.allowsAuthorization(host: "localhost"))
        #expect(HostTrustPolicy.allowsAuthorization(host: "LOCALHOST"))
    }
}
