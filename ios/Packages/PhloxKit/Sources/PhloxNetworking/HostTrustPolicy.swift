import Foundation

/// Authorization（Bearer トークン）を付与してよい接続先かの判定（純関数）。
/// レビュー #3（CWE-319: ATS 全体無効化＋http 固定下のトークン平文送信）へのクライアント側ガード。
/// ゲート①決定: ATS 設定は温存し、信頼できる host（Tailscale / プライベートレンジ）以外には
/// Authorization ヘッダーを付けない（設計判断は ADR 化。task-3）。
/// 契約は Tests/PhloxNetworkingTests/HostTrustPolicyAcceptanceTests.swift。
public enum HostTrustPolicy {
    /// 信頼できる接続先なら true:
    /// - `*.ts.net`（Tailscale MagicDNS。ドット境界で判定し "evil-ts.net" は不可）
    /// - 100.64.0.0/10（Tailscale が使う CGNAT レンジ）
    /// - RFC1918 プライベート（10/8・172.16/12・192.168/16）
    /// - loopback（localhost・127.0.0.0/8）
    public static func allowsAuthorization(host: String) -> Bool {
        let normalizedHost = host.lowercased()
        if normalizedHost == "localhost" {
            return true
        }
        if isTailscaleMagicDNS(normalizedHost) {
            return true
        }
        guard let address = parseIPv4(normalizedHost) else {
            return false
        }

        return isInCIDR(address, base: 0x6440_0000, prefixLength: 10)
            || isInCIDR(address, base: 0x0A00_0000, prefixLength: 8)
            || isInCIDR(address, base: 0xAC10_0000, prefixLength: 12)
            || isInCIDR(address, base: 0xC0A8_0000, prefixLength: 16)
            || isInCIDR(address, base: 0x7F00_0000, prefixLength: 8)
    }

    private static func isTailscaleMagicDNS(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3, labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return labels[labels.count - 2] == "ts" && labels[labels.count - 1] == "net"
    }

    private static func parseIPv4(_ host: String) -> UInt32? {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return nil
        }

        var address: UInt32 = 0
        for octet in octets {
            guard !octet.isEmpty,
                  !(octet.count > 1 && octet.first == "0") else {
                return nil
            }

            var value: UInt32 = 0
            for byte in octet.utf8 {
                guard byte >= 48, byte <= 57 else {
                    return nil
                }
                value = value * 10 + UInt32(byte - 48)
                guard value <= 255 else {
                    return nil
                }
            }
            address = (address << 8) | value
        }
        return address
    }

    private static func isInCIDR(_ address: UInt32, base: UInt32, prefixLength: UInt32) -> Bool {
        let mask = UInt32.max << (32 - prefixLength)
        return address & mask == base & mask
    }
}
