import Foundation

/// QR ペアリング用 URL 生成の検証エラー。`token` はメッセージへ含めない。
public enum PairingPayloadError: Error, Equatable, Sendable {
    case invalidHost
    case invalidPort
    case invalidToken
    case unsupportedBindMode
}

/// QR ペアリング契約 v1 のペイロード（`phlox://pair?...` URL 文字列）。
public struct PairingPayload: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let token: String
    public let name: String?
    public let urlString: String

    /// 検証済みフィールドからペイロードを生成する。
    public static func make(
        host: String,
        port: Int,
        token: String,
        name: String? = nil
    ) -> Result<PairingPayload, PairingPayloadError> {
        guard Self.isIPv4(host) else {
            return .failure(.invalidHost)
        }
        guard (1 ... 65_535).contains(port) else {
            return .failure(.invalidPort)
        }
        guard Self.isValidToken(token) else {
            return .failure(.invalidToken)
        }

        var url = "phlox://pair?v=1&host=\(host)&port=\(port)&token=\(token)"
        if let name {
            url += "&name=\(Self.percentEncodeName(name))"
        }

        return .success(
            PairingPayload(host: host, port: port, token: token, name: name, urlString: url)
        )
    }

    /// `BindMode` から host を導出してペイロードを生成する。
    /// `.tailscale(ip)` のみ成功。`.loopbackOnly` および `.explicitHost` は生成不可。
    public static func make(
        bindMode: BindMode,
        port: Int,
        token: String,
        name: String? = nil
    ) -> Result<PairingPayload, PairingPayloadError> {
        switch bindMode {
        case .tailscale(let ip):
            return make(host: ip, port: port, token: token, name: name)
        case .loopbackOnly, .explicitHost:
            return .failure(.unsupportedBindMode)
        }
    }

    /// ドット区切り 4 オクテット（各 0...255）を IPv4 とみなす。
    private static func isIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let value = Int(part), value >= 0, value <= 255,
                  part.allSatisfy(\.isNumber)
            else {
                return false
            }
        }
        return true
    }

    /// 64 文字の 16 進小文字 `[0-9a-f]{64}`。
    private static func isValidToken(_ token: String) -> Bool {
        guard token.count == 64 else { return false }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        return token.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }

    /// RFC 3986 unreserved（ALPHA / DIGIT / `-` `.` `_` `~`）以外を percent-encode する。
    private static func percentEncodeName(_ name: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // UTF-8 の Swift String は常に percent-encoding 可能。
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
