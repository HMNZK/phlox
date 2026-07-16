import Foundation
import Features
import PhloxCore
import PhloxNetworking
import PhloxSecurity

@available(iOS 17.2, *)
actor LiveActivityPushRegistration: LiveActivityTokenRegistering {
    private let configProvider: @Sendable () -> ConnectionConfig
    private let tokenStore: any TokenStore
    private let session: URLSession

    init(
        configProvider: @escaping @Sendable () -> ConnectionConfig = UserDefaultsConnectionConfigStore.liveProvider,
        tokenStore: any TokenStore = KeychainStore(),
        session: URLSession = .shared
    ) {
        self.configProvider = configProvider
        self.tokenStore = tokenStore
        self.session = session
    }

    func registerLiveActivityToken(_ registration: LiveActivityTokenRegistration) async throws {
        let config = configProvider()
        guard !config.host.isEmpty,
              HostTrustPolicy.allowsAuthorization(host: config.host),
              let url = URL(string: "http://\(config.host):\(config.port)/device-tokens"),
              let bearerToken = try await tokenStore.load(),
              !bearerToken.isEmpty
        else {
            throw URLError(.notConnectedToInternet)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(registration)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
