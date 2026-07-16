import Foundation

public enum PTYError: Error, Sendable, Equatable {
    case sessionNotFound
    case openPTYFailed(errno: Int32)
    case spawnFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case killFailed(errno: Int32)
    case resizeFailed(errno: Int32)
}
