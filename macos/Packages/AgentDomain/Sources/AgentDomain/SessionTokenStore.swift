import Foundation

public actor SessionTokenStore {
    private var tokenToSession: [String: SessionID] = [:]
    private var sessionToToken: [SessionID: String] = [:]

    public init() {}

    public func register(_ token: String, for session: SessionID) {
        // 空文字列は無効なトークンとして完全に無視する（既存マッピングも変更しない）。
        guard !token.isEmpty else { return }
        if let oldToken = sessionToToken[session] {
            tokenToSession.removeValue(forKey: oldToken)
        }
        if let oldSession = tokenToSession[token] {
            sessionToToken.removeValue(forKey: oldSession)
        }
        tokenToSession[token] = session
        sessionToToken[session] = token
    }

    public func remove(session: SessionID) {
        guard let token = sessionToToken.removeValue(forKey: session) else { return }
        tokenToSession.removeValue(forKey: token)
    }

    public func session(forToken token: String) -> SessionID? {
        tokenToSession[token]
    }

    public func token(for session: SessionID) -> String? {
        sessionToToken[session]
    }
}
