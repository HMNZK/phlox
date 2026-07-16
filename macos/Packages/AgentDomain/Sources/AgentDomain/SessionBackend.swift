import Foundation

public enum SessionBackend: String, Sendable, Codable, Hashable {
    case pty
    case appServer
}
