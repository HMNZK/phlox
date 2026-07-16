import Testing
@testable import AgentDomain

@Test func sessionTokenStore_registerEnablesBidirectionalLookup() async {
    let store = SessionTokenStore()
    let session = SessionID()

    await store.register("token-a", for: session)

    #expect(await store.session(forToken: "token-a") == session)
    #expect(await store.token(for: session) == "token-a")
}

@Test func sessionTokenStore_reRegisteringSessionInvalidatesOldToken() async {
    let store = SessionTokenStore()
    let session = SessionID()
    await store.register("token-old", for: session)

    await store.register("token-new", for: session)

    #expect(await store.session(forToken: "token-old") == nil)
    #expect(await store.session(forToken: "token-new") == session)
    #expect(await store.token(for: session) == "token-new")
}

@Test func sessionTokenStore_reassigningTokenInvalidatesOldSessionLookup() async {
    let store = SessionTokenStore()
    let oldSession = SessionID()
    let newSession = SessionID()
    await store.register("token-shared", for: oldSession)

    await store.register("token-shared", for: newSession)

    #expect(await store.token(for: oldSession) == nil)
    #expect(await store.session(forToken: "token-shared") == newSession)
    #expect(await store.token(for: newSession) == "token-shared")
}

@Test func sessionTokenStore_removeClearsBothDirections() async {
    let store = SessionTokenStore()
    let session = SessionID()
    await store.register("token-r", for: session)

    await store.remove(session: session)

    #expect(await store.session(forToken: "token-r") == nil)
    #expect(await store.token(for: session) == nil)
}
