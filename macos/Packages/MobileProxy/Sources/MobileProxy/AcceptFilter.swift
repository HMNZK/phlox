import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// accept 時の「接続元(remote peer)IP の CIDR フィルタ」。
///
/// 実機データで判明した事実:
/// - getsockname(ローカル宛先 IP)は iPhone も Mac 自身の hairpin も同一(100.64.0.10)で、
///   判定に使えない。差が出るのは getpeername(接続元 IP)だけ。
/// - そこで「接続元 IP が許可 CIDR に入るか」で判定する。Tailscale ピアは必ず CGNAT 範囲
///   100.64.0.0/10。iPhone=100.64.0.20 / Mac hairpin=100.64.0.10 は範囲内 → 許可。
///   LAN(172.16/12・192.168/16・10/8)やグローバルは範囲外 → 拒否。loopback テストは 127.0.0.0/8。
///
/// 0.0.0.0 bind(macOS は utun 特定 IP bind へ着信を配送しないため必須)で全 IF に listen しても、
/// このフィルタで Tailscale ピア / loopback 以外の接続元を ControlServer へ中継しない。
///
/// 多層防御(重要): この CIDR フィルタは「送信元 IP の詐称は Tailscale/OS 経路で困難」という前提の
/// **一次的**な露出低減にすぎない。0.0.0.0 bind で全 IF に listen する構成における**最終防御は、
/// 転送先 ControlServer が行う Bearer トークン検証**である。CIDR を通過して中継された接続でも、
/// 有効な Bearer が無ければ ControlServer が拒否する。ここは fail-closed(不明/取得不能な接続元は
/// 拒否)を保つが、認証そのものはこの層の責務ではない(生 TCP リレーは透過。ADR 参照)。
public enum AcceptFilter: Sendable {
    /// 接続元 IP が許可 CIDR のいずれかに含まれるか(純関数・テスト可能)。
    /// - remoteIP: getpeername で得た接続元 IPv4。取得不能・不正は nil。
    /// - allowedCIDRs: 許可する CIDR 文字列(例 "100.64.0.0/10")。空なら何も許可しない(fail-closed)。
    public static func shouldAccept(remoteIP: String?, allowedCIDRs: [String]) -> Bool {
        guard let remoteIP, let value = ipv4ToUInt32(remoteIP) else {
            return false
        }
        for cidr in allowedCIDRs {
            if cidrContains(cidr, value: value) {
                return true
            }
        }
        return false
    }

    /// CIDR("a.b.c.d/prefix")が value(ネットワークバイトオーダではなくホスト数値)を含むか。
    static func cidrContains(_ cidr: String, value: UInt32) -> Bool {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let base = ipv4ToUInt32(String(parts[0])),
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32
        else {
            return false
        }
        if prefix == 0 {
            return true
        }
        let mask: UInt32 = prefix == 32 ? .max : ~(UInt32.max >> UInt32(prefix))
        return (value & mask) == (base & mask)
    }

    /// ドット区切り IPv4 文字列をホスト順 UInt32 へ変換する。不正なら nil。
    static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let octets = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var result: UInt32 = 0
        for octet in octets {
            guard !octet.isEmpty,
                  octet.allSatisfy(\.isNumber),
                  let n = UInt32(octet),
                  n <= 255
            else {
                return nil
            }
            result = (result << 8) | n
        }
        return result
    }

    /// 受理済み client fd の「接続元(remote peer)IP」を getpeername で取る。IPv4 のみ。
    /// 取得不能・非 IPv4 は nil。
    static func remotePeerIP(ofFD fd: Int32) -> String? {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getpeername(fd, sa, &len)
            }
        }
        guard result == 0 else { return nil }
        return ipv4String(from: &addr)
    }

    /// sockaddr_storage(IPv4)から表示用 IP 文字列を作る。非 IPv4 は nil。
    static func ipv4String(from storage: inout sockaddr_storage) -> String? {
        guard Int32(storage.ss_family) == AF_INET else { return nil }
        return withUnsafePointer(to: &storage) { ptr in
            ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var inAddr = sin.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return buffer.withUnsafeBufferPointer { buf in
                    buf.baseAddress.map { String(cString: $0) }
                }
            }
        }
    }
}
