import AgentDomain
import Foundation
import Testing
@testable import ControlServer

private actor QuestionWhiteboxHandlerStub {
  private(set) var lastAction: ControlRequest.Action?

  func handle(_ request: ControlRequest) -> ControlResponse {
    lastAction = request.action
    return .status(200)
  }
}

@Suite struct UserQuestionRoutingWhiteboxTests {
  private let requester = SessionID()
  private let bearer = "question-whitebox-bearer"

  @Test func postQuestionWithQueryReturns404WithoutHandler() async throws {
    let stub = QuestionWhiteboxHandlerStub()
    let (port, server) = try await startServer(stub)
    _ = server
    let target = SessionID()

    let response = try await request(
      port: port,
      method: "POST",
      path: "/sessions/\(target.rawValue.uuidString)\(ControlQuestionWireContract.questionPathSuffix)?x=1",
      body: #"{"requestId":"req-1","answers":{"Q":["A"]}}"#
    )

    #expect(response.statusCode == 404)
    #expect(await stub.lastAction == nil)
  }

  @Test func postQuestionInvalidSessionIDReturns400() async throws {
    let stub = QuestionWhiteboxHandlerStub()
    let (port, server) = try await startServer(stub)
    _ = server

    let response = try await request(
      port: port,
      method: "POST",
      path: "/sessions/not-a-uuid\(ControlQuestionWireContract.questionPathSuffix)",
      body: #"{"requestId":"req-1","answers":{"Q":["A"]}}"#
    )

    #expect(response.statusCode == 400)
    #expect(await stub.lastAction == nil)
  }

  private func startServer(_ stub: QuestionWhiteboxHandlerStub) async throws -> (Int, ControlServer) {
    let store = SessionTokenStore()
    await store.register(bearer, for: requester)
    let server = ControlServer(tokenStore: store) { request in
      await stub.handle(request)
    }
    return (try await server.start(), server)
  }

  private func request(
    port: Int,
    method: String,
    path: String,
    body: String? = nil
  ) async throws -> HTTPURLResponse {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = method
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = Data(body.utf8)
    }
    let (_, response) = try await URLSession.shared.data(for: request)
    return try #require(response as? HTTPURLResponse)
  }
}
