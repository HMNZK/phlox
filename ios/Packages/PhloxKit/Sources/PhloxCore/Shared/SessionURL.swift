import Foundation

public enum SessionURL {
    public static func make(sessionID: String) -> URL? {
        guard isValidID(sessionID) else { return nil }
        return URL(string: "phlox://session/\(sessionID)")
    }

    public static func sessionID(from url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "phlox", parts.host == "session",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath == parts.path,
              parts.path.hasPrefix("/") else { return nil }
        let id = String(parts.path.dropFirst())
        return isValidID(id) ? id : nil
    }

    private static func isValidID(_ id: String) -> Bool {
        guard 1...128 ~= id.utf8.count else { return false }
        return id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
