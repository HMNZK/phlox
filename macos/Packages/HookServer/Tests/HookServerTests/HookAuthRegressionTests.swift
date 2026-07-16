import AgentDomain
import Foundation
import Testing
@testable import HookServer

/// A1（監査）回帰: hook POST の認証。tokenStore を注入した HookServer は
/// `Authorization: Bearer <token>` を要求し、token↔session を検証する。
/// - token 無し / 未知 token → 拒否（イベント非配送）
/// - 正当 token だが payload.sessionId が別セッション → 403（偽注入拒否・かつ非配送）
/// - 正当 token かつ payload.sessionId と一致 → 200 で配送
///
/// HTTP クライアントは実クライアント（hook-dispatcher.sh）と同じ curl を用いる。
/// 中核はセキュリティ不変条件＝「認証を通らない POST では hook イベントが配送されない
/// （偽 stop/idle 注入が起きない）」であり、これを events ストリームで直接検証する。
/// 補足: token 無し等の早期拒否は本文処理を挟まず即 close するため、TCP close が
/// クライアント側の pending 送信データと競合して環境により connection reset になり得る
/// （sendAndClose 自体は graceful cancel=FIN。RST は「未読データを持つソケットの close」という
/// POSIX 挙動で、実クライアントの curl は `|| true` で無視する）。よって早期拒否は非配送で、
/// actor ホップを挟む 403（別セッション）と 200（正当）はステータスも検証する。
@Suite struct HookAuthRegressionTests {
    private func startAuthedServer(
        register: (SessionID, String)?
    ) async throws -> (server: HookServer, port: Int) {
        let tokenStore = SessionTokenStore()
        if let (session, token) = register {
            await tokenStore.register(token, for: session)
        }
        let server = HookServer(tokenStore: tokenStore)
        let port = try await server.start()
        return (server, port)
    }

    /// curl で POST し、HTTP ステータスコードを返す。
    private func postHookStatus(port: Int, body: String, bearer: String?) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = [
            "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--max-time", "5",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "--data-binary", body,
        ]
        if let bearer {
            args.append(contentsOf: ["-H", "Authorization: Bearer \(bearer)"])
        }
        args.append("http://127.0.0.1:\(port)/hook")
        process.arguments = args

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(text) ?? -1
    }

    /// server.events から `within` ナノ秒以内に最初のイベントを取り出す。時間内に来なければ nil。
    private func firstEvent(
        _ server: HookServer,
        within nanoseconds: UInt64
    ) async -> (SessionID, HookEvent)? {
        await withTaskGroup(of: (SessionID, HookEvent)?.self) { group in
            group.addTask {
                var iterator = server.events.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    @Test func postWithoutTokenIsRejectedAndNotDelivered() async throws {
        let session = SessionID()
        let (server, port) = try await startAuthedServer(register: (session, "valid-token"))
        _ = try postHookStatus(
            port: port,
            body: #"{"sessionId":"\#(session.rawValue.uuidString)","kind":"sessionStart"}"#,
            bearer: nil
        )
        let delivered = await firstEvent(server, within: 400_000_000)
        #expect(delivered == nil, "未認証 POST が hook として配送された（偽注入）")
    }

    @Test func postWithUnknownTokenIsRejectedAndNotDelivered() async throws {
        let session = SessionID()
        let (server, port) = try await startAuthedServer(register: (session, "valid-token"))
        _ = try postHookStatus(
            port: port,
            body: #"{"sessionId":"\#(session.rawValue.uuidString)","kind":"sessionStart"}"#,
            bearer: "wrong-token"
        )
        let delivered = await firstEvent(server, within: 400_000_000)
        #expect(delivered == nil, "不正トークンの POST が配送された")
    }

    @Test func postWithValidTokenForDifferentSessionReturns403AndIsNotDelivered() async throws {
        let ownSession = SessionID()
        let otherSession = SessionID()
        let token = "own-token-\(UUID().uuidString)"
        // token は ownSession に紐づくが、payload は otherSession の hook を注入しようとする。
        let (server, port) = try await startAuthedServer(register: (ownSession, token))

        let status = try postHookStatus(
            port: port,
            body: #"{"sessionId":"\#(otherSession.rawValue.uuidString)","kind":"stop","exitCode":0}"#,
            bearer: token
        )
        #expect(status == 403)

        // セキュリティ不変条件: 別セッションの hook はイベントとして配送されない（偽注入拒否）。
        let delivered = await firstEvent(server, within: 400_000_000)
        #expect(delivered == nil, "別セッションの hook が有効トークンで注入された（IDOR）")
    }

    @Test func postWithValidTokenMatchingSessionReturns200AndDelivers() async throws {
        let session = SessionID()
        let token = "valid-token-\(UUID().uuidString)"
        let (server, port) = try await startAuthedServer(register: (session, token))

        let status = try postHookStatus(
            port: port,
            body: #"{"sessionId":"\#(session.rawValue.uuidString)","kind":"sessionStart"}"#,
            bearer: token
        )
        #expect(status == 200)

        let delivered = await firstEvent(server, within: 1_000_000_000)
        #expect(delivered?.0 == session)
        #expect(delivered?.1 == .sessionStart)
    }
}
