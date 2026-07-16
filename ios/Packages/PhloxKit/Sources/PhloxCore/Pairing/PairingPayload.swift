import Foundation

/// 契約 v1: phlox://pair?v=1&host=<IPv4>&port=<1-65535>&token=<[0-9a-f]{64}>&name=<percent-encoded 任意>
public struct PairingPayload: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let token: String
    public let name: String?

    public init(host: String, port: Int, token: String, name: String?) {
        self.host = host
        self.port = port
        self.token = token
        self.name = name
    }
}

public enum PairingPayloadError: Error, Sendable, Equatable {
    case notPairingURL
    case unsupportedVersion(String?)
    case missingHost
    case invalidPort
    case invalidToken
}

public enum PairingPayloadParser {
    /// 検証順序は固定: notPairingURL → unsupportedVersion → missingHost → invalidPort → invalidToken。
    /// 未知のクエリパラメータは無視（前方互換）。同名パラメータ重複は最初の値を採用。
    /// パラメータ順序には依存しない。
    public static func parse(_ string: String) -> Result<PairingPayload, PairingPayloadError> {
        guard let components = URLComponents(string: string),
              components.scheme == "phlox",
              components.host == "pair"
        else {
            return .failure(.notPairingURL)
        }

        let queryItems = components.queryItems ?? []

        func firstValue(named name: String) -> String? {
            queryItems.first { $0.name == name }?.value
        }

        guard let version = firstValue(named: "v") else {
            return .failure(.unsupportedVersion(nil))
        }
        guard version == "1" else {
            return .failure(.unsupportedVersion(version))
        }

        guard let host = firstValue(named: "host"), !host.isEmpty else {
            return .failure(.missingHost)
        }

        guard let portString = firstValue(named: "port"),
              let port = Int(portString),
              (1 ... 65535).contains(port)
        else {
            return .failure(.invalidPort)
        }

        guard let token = firstValue(named: "token"),
              isValidToken(token)
        else {
            return .failure(.invalidToken)
        }

        let rawName = firstValue(named: "name")
        let name: String? = {
            guard let rawName, !rawName.isEmpty else { return nil }
            return rawName
        }()

        return .success(PairingPayload(host: host, port: port, token: token, name: name))
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.count == 64 && token.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
