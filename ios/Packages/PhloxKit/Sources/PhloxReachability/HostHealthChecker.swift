import Foundation
import PhloxCore

/// `GET /sessions` の応答可否だけで Phlox ホストの生存を確認する（ボディは捨てる）。
/// HTTP 応答が返れば（401 等でも）ホストは生きているとみなす。エラー/タイムアウトで false。
public struct HostHealthChecker: Sendable {
    let session: URLSession
    let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.session = session
        self.timeout = timeout
    }

    public func isHostReachable(baseURL: URL, token: String?) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
