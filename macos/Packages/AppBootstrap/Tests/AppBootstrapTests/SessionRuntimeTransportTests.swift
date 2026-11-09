import Foundation
import Darwin
import AgentDomain
import SessionFeature
@testable import DashboardFeature
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeTransportTests {
    @Test(arguments: [
        DashboardRuntimeCommand.session(SessionID(), UUID(), .send(
            text: "send-before-snapshot", submit: true, attachments: [], skill: nil)),
        DashboardRuntimeCommand.session(SessionID(), UUID(), .sendControlSkill(
            text: "review-before-snapshot", submit: true, attachments: [],
            skill: .init(name: "review", path: "/skills/review/SKILL.md", runtimeFingerprint: "review-fingerprint"))),
    ])
    @MainActor func acceptedSendsReturnWhileSnapshotDecodeIsBlocked(command: DashboardRuntimeCommand) async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let receipt = try #require(UUID(uuidString: "134D69F2-E836-4BB6-BB3E-FC1F5875BAEF"))
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: { .init(projects: [], sessions: [], availableAgentKinds: []) },
            command: { _ in .session(.accepted(receipt)) }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let gate = SaturatedSnapshotDecodeGate()
        defer { gate.release() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            gate.started.continuation.finish()
            gate.release()
        }
        let client = SessionRuntimeClient(endpoint: endpoint, snapshotDecoder: gate.decode,
            snapshotUpdateDecoder: gate.decodeUpdate)
        client.onCommandSnapshot = { _ in }
        try await client.handshake()
        var entered = gate.started.stream.makeAsyncIterator()
        let first = Task { try await client.snapshot() }
        let second = Task { try await client.snapshot() }
        #expect(await entered.next() != nil)
        #expect(await entered.next() != nil)

        let reply = try await client.command(command)

        #expect(!gate.isReleased, "The acceptance reply must return before snapshot decoding resumes")
        guard case .session(.accepted(let actualReceipt)) = reply else {
            Issue.record("The send did not return its acceptance receipt")
            return
        }
        #expect(actualReceipt == receipt)
        gate.release()
        _ = try await first.value
        _ = try await second.value
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func acceptedCommandWaitsForSaturatedSnapshotQueue() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let handled = AsyncStream<Void>.makeStream()
        var snapshots = 0
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                snapshots += 1
                return .init(projects: [], sessions: [], availableAgentKinds: [])
            },
            command: { _ in handled.continuation.yield(); return .none }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let gate = SaturatedSnapshotDecodeGate()
        defer { gate.release() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { gate.release() }
        let client = SessionRuntimeClient(endpoint: endpoint, snapshotDecoder: gate.decode)
        client.onCommandSnapshot = { _ in }
        var entered = gate.started.stream.makeAsyncIterator()
        let first = Task { try await client.snapshot() }
        let second = Task { try await client.snapshot() }
        _ = await entered.next()
        _ = await entered.next()

        let queued = AsyncStream<Void>.makeStream()
        var queuedEvents = queued.stream.makeAsyncIterator()
        var waiting: [Task<DashboardRuntimeSnapshot, Error>] = []
        for _ in 0..<8 {
            waiting.append(Task { queued.continuation.yield(); return try await client.snapshot() })
            _ = await queuedEvents.next()
        }
        let sending = Task { try await client.command(.session(SessionID(), UUID(), .interrupt)) }
        var handledEvents = handled.stream.makeAsyncIterator()
        _ = await handledEvents.next()
        try await Task.sleep(for: .milliseconds(300))
        #expect(snapshots == 2)
        gate.release()
        _ = try await first.value
        _ = try await second.value
        for task in waiting { _ = try await task.value }
        _ = try await sending.value
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func delayedSnapshotDecodeDoesNotBlockNewerSnapshotAndCancellation() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        var snapshots = 0
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                snapshots += 1
                return .init(projects: [], sessions: [], availableAgentKinds: snapshots == 1 ? [.codex] : [.claudeCode])
            },
            command: { _ in .none }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let gate = SnapshotDecodeGate()
        defer { gate.releaseAll() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { gate.releaseAll() }
        let client = SessionRuntimeClient(endpoint: endpoint, snapshotDecoder: gate.decode)
        var events = gate.started.stream.makeAsyncIterator()

        let first = Task { try await client.snapshot() }
        #expect(await events.next() == 1)
        let newer = try await client.snapshot()
        #expect(newer.availableAgentKinds == [.claudeCode])
        gate.first.signal()
        let retried = try await first.value
        #expect(retried.availableAgentKinds == [.claudeCode])

        let cancelled = Task { try await client.snapshot() }
        #expect(await events.next() == 4)
        cancelled.cancel()
        gate.fourth.signal()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        await #expect(throws: SnapshotDecodeGate.Failure.self) { _ = try await client.snapshot() }
        #expect(try await client.snapshot().availableAgentKinds == [.claudeCode])
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func controlSkillsRequireAdvertisedOwnerSupportWithoutBreakingOldCommands() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let selection = AgentSkillSelection(name: "review", path: "/skills/review/SKILL.md", runtimeFingerprint: "hash")
        var handled = 0
        var receivedSkills: [AgentSkillSelection?] = []
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: { .init(projects: [], sessions: [], availableAgentKinds: []) },
            command: { command in
                handled += 1
                switch command {
                case .message(let request):
                    receivedSkills.append(request.skill)
                case .session(_, _, .sendControlSkill(_, _, _, let skill)):
                    #expect(skill.name == selection.name && skill.path == selection.path && skill.runtimeFingerprint == selection.runtimeFingerprint)
                default: Issue.record("unexpected command")
                }
                return .none
            })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let client = SessionRuntimeClient(endpoint: endpoint)
        let message = DashboardRuntimeCommand.message(.init(recipient: .id(SessionID()), text: "$review inspect",
            submit: true, from: nil, inReplyTo: nil, images: [], skill: selection))
        let session = DashboardRuntimeCommand.session(SessionID(), UUID(), .sendControlSkill(text: "$review inspect", submit: true,
            attachments: [], skill: .init(name: selection.name, path: selection.path, runtimeFingerprint: selection.runtimeFingerprint)))
        try await client.handshake()
        _ = try await client.command(message)
        _ = try await client.command(session)
        #expect(handled == 2)
        #expect(receivedSkills == [selection])
        let legacy = try JSONDecoder().decode(SessionRuntimeHandshake.self,
            from: Data("{\"protocolVersion\":1,\"generation\":\"\(generation)\"}".utf8))
        try client.acceptHandshake(legacy)
        for command in [message, session] {
            await #expect(throws: SessionRuntimeConnectionError.incompatibleProtocol) {
                _ = try await client.command(command)
            }
        }
        #expect(handled == 2)
        _ = try await client.command(.message(.init(recipient: .id(SessionID()), text: "ordinary",
            submit: true, from: nil, inReplyTo: nil, images: [])))
        #expect(handled == 3)
        #expect(receivedSkills == [selection, nil])
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test func fullNormalPendingByteBudgetPreservesUrgentExecutionAndDeduplication() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumBytes: 32 * 1024)
        let blocked = RuntimeHeldCommands()
        let firstOperation = SessionRuntimeOperation(generation: generation, payload: Data(repeating: 1, count: 14 * 1024))
        let secondOperation = SessionRuntimeOperation(generation: generation, payload: Data(repeating: 2, count: 14 * 1024))
        let first = Task {
            do { return try await ledger.perform(firstOperation, maximumResultBytes: 0) { await blocked.wait() } }
            catch { blocked.entered.continuation.finish(); throw error }
        }
        let second = Task {
            do { return try await ledger.perform(secondOperation, maximumResultBytes: 0) { await blocked.wait() } }
            catch { blocked.entered.continuation.finish(); throw error }
        }
        var entered = blocked.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        _ = await entered.next()
        do {
            await #expect(throws: SessionRuntimeConnectionError.self) {
                _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
            }
            let urgent = SessionRuntimeOperation(generation: generation, payload: Data())
            let counter = RuntimeCommandCounter()
            let value = try await ledger.perform(urgent, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
            let replay = try await ledger.perform(urgent, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
            #expect(value == replay)
            #expect(await counter.value == 1)
        } catch {
            await blocked.release()
            _ = try await first.value
            _ = try await second.value
            throw error
        }
        await blocked.release()
        _ = try await first.value
        _ = try await second.value
    }

    @Test func fullNormalRetainedByteBudgetPreservesUrgentExecution() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumBytes: 32 * 1024)
        _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 29 * 1024) {
            Data(repeating: 1, count: 29 * 1024)
        }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        let result = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 1024, urgent: true) { Data([7]) }
        #expect(result == Data([7]))
    }

    @Test func fullNormalEntryBudgetPreservesUrgentEntryAndDeduplication() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumOperations: 32)
        for _ in 0..<30 {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        let operation = SessionRuntimeOperation(generation: generation, payload: Data())
        let counter = RuntimeCommandCounter()
        _ = try await ledger.perform(operation, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
        _ = try await ledger.perform(operation, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
        #expect(await counter.value == 1)
    }

    @Test func snapshotLeaseStartsAtFetchAndExpiresAfterThirtyFiveSeconds() {
        let start = ContinuousClock.now
        let value = SessionRuntimeReceivedSnapshot(
            envelope: .init(sequence: 1, snapshot: .init(projects: [], sessions: [], availableAgentKinds: [])),
            startedAt: start
        )
        #expect(value.isFresh(at: start + .seconds(35)))
        #expect(!value.isFresh(at: start + .seconds(35) + .nanoseconds(1)))
    }

    @Test func twoMinutesOfTwentyKeysPerSecondAreDeliveredAndRemainDeduplicated() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let start = Date()
        let recorder = RuntimeKeyRecorder()
        var operations: [SessionRuntimeOperation] = []
        var expected = Data()
        for index in 0..<2400 {
            let key = Data([UInt8(index % 26 + 97)])
            expected.append(key)
            let instant = start.addingTimeInterval(Double(index) / 20)
            let operation = SessionRuntimeOperation(generation: generation, issuedAt: instant, payload: key)
            operations.append(operation)
            _ = try await ledger.perform(operation, now: instant) { await recorder.append(key) }
        }
        for operation in [operations[0], operations[2399]] {
            _ = try await ledger.perform(operation, now: start.addingTimeInterval(119.99)) {
                await recorder.append(operation.payload)
            }
        }
        #expect(await recorder.input == expected)
    }

    @Test @MainActor func pendingCommandAllowsSameClientReadsAndInterruptAndOtherClientHandshake() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let probe = RuntimePendingTurn()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                probe.snapshotsWhilePending += probe.completed ? 0 : 1
                return .init(projects: [], sessions: [], availableAgentKinds: [])
            },
            command: { command in
                switch command {
                case .session(_, _, .send): await probe.start()
                case .session(_, _, .interrupt): probe.interrupt()
                default: break
                }
                return .none
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation, token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let client = SessionRuntimeClient(endpoint: endpoint)
        let sessionID = SessionID()
        let executionID = UUID()
        let sending = Task { try await client.command(.session(sessionID, executionID, .send(text: "run", submit: true, attachments: [], skill: nil))) }
        var entered = probe.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            probe.release()
        }
        defer { watchdog.cancel(); probe.release() }
        try await SessionRuntimeClient(endpoint: endpoint).handshake()
        _ = try await client.snapshot()
        _ = try await client.command(.session(sessionID, executionID, .interrupt))
        _ = try await sending.value
        #expect(probe.starts == 1)
        #expect(probe.snapshotsWhilePending > 0)
        #expect(probe.interruptedWhilePending)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func retriedPendingHTTPCommandExecutesOnceWhileControlsRemainAvailable() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let probe = RuntimePendingTurn()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                probe.snapshotsWhilePending += probe.completed ? 0 : 1
                return .init(projects: [], sessions: [], availableAgentKinds: [])
            },
            command: { command in
                switch command {
                case .session(_, _, .send): await probe.start()
                case .session(_, _, .interrupt): probe.interrupt()
                default: break
                }
                return .none
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation, token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let sessionID = SessionID()
        let executionID = UUID()
        let command = DashboardRuntimeCommand.session(sessionID, executionID, .send(text: "run", submit: true, attachments: [], skill: nil))
        let operation = SessionRuntimeOperation(generation: generation, payload: try JSONEncoder().encode(command))
        let first = Task { try await runtimeHTTPCommand(operation, endpoint: endpoint) }
        var entered = probe.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        let duplicate = Task { try await runtimeHTTPCommand(operation, endpoint: endpoint) }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            probe.release()
        }
        defer { watchdog.cancel(); probe.release() }
        let reattached = SessionRuntimeClient(endpoint: endpoint)
        try await reattached.handshake()
        _ = try await reattached.snapshot()
        _ = try await reattached.command(.session(sessionID, executionID, .interrupt))
        let firstReply = try await first.value
        let duplicateReply = try await duplicate.value
        #expect(firstReply == duplicateReply)
        #expect(probe.starts == 1)
        #expect(probe.snapshotsWhilePending > 0)
        #expect(probe.interruptedWhilePending)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }
    @Test func imageDraftLimitsAccountForNestedBase64WithoutChangingSnapshotLimit() {
        let rawBytes = ImageAttachmentLimits.maxTotalInputBytes
        let innerJSONBytes = ((rawBytes + 2) / 3) * 4
        let outerJSONBytes = ((innerJSONBytes + 2) / 3) * 4
        #expect(SessionRuntimeTransport.maximumRequestBytes > outerJSONBytes)
        #expect(SessionRuntimeTransport.maximumCommandReplyBytes > innerJSONBytes)
        #expect(SessionRuntimeTransport.maximumSnapshotBytes == 64 * 1024 * 1024)
        #expect(SessionRuntimeTransport.maximumRequestBytes == 160 * 1024 * 1024)
        #expect(SessionRuntimeTransport.maximumCommandReplyBytes == 128 * 1024 * 1024)
    }

    @Test @MainActor func overviewUsesItsOwnAuthenticatedEndpointWithoutFullSnapshot() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: { throw SessionRuntimeConnectionError.rejected("Full snapshot must not run") },
            overview: { .init(projects: [], sessions: [], availableAgentKinds: [.codex]) },
            command: { _ in .none }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let token = try SessionRuntimeCredentialStore.load(storeURL: fixture.url)

        let valid = try await runtimeHTTPOverview(url: url, token: token, generation: generation)
        let unauthorized = try await runtimeHTTPOverview(url: url, token: "wrong-token", generation: generation)
        let stale = try await runtimeHTTPOverview(url: url, token: token, generation: UUID())

        #expect(valid.status == 200)
        #expect(try JSONDecoder().decode(SessionRuntimeOverviewEnvelope.self, from: valid.data).overview.availableAgentKinds == [.codex])
        #expect(unauthorized.status == 401)
        #expect(stale.status == 409)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func contentEndpointAuthenticatesAndDistinguishesStalePage() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let sessionID = SessionID()
        let executionID = UUID()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: { throw SessionRuntimeConnectionError.rejected("Full snapshot must not run") },
            content: { request in
                if case .chatBefore = request.target { throw SessionRuntimeContentError.staleContent }
                if case .chatPresentation = request.target { throw SessionRuntimeContentError.invalidRequest }
                return .chatPage(.init(sessionID: request.sessionID, executionID: request.executionID,
                    transcriptRevision: 7, totalCount: 0, startIndex: 0,
                    entries: [], olderCursor: nil, turnUsageByItemID: [:]))
            }, command: { _ in .none }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let token = try SessionRuntimeCredentialStore.load(storeURL: fixture.url)
        let tail = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID, target: .chatTail)
        let old = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID,
            target: .chatBefore(cursor: .init(index: 1, anchorID: "item", prefixDigest: "digest")))
        let invalid = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID,
            target: .chatPresentation(offset: 0, digest: nil))

        let valid = try await runtimeHTTPContent(url: url, token: token, generation: generation, request: tail)
        let unauthorized = try await runtimeHTTPContent(url: url, token: "wrong-token", generation: generation, request: tail)
        let staleGeneration = try await runtimeHTTPContent(url: url, token: token, generation: UUID(), request: tail)
        let stalePage = try await runtimeHTTPContent(url: url, token: token, generation: generation, request: old)
        let malformed = try await runtimeHTTPContent(url: url, token: token, generation: generation, encodedRequest: "not-base64")

        #expect(valid.status == 200)
        #expect(valid.data.count <= SessionRuntimeContentLimits.maximumResponseBytes)
        #expect(unauthorized.status == 401)
        #expect(staleGeneration.status == 409)
        #expect(stalePage.status == 412)
        #expect(malformed.status == 400)
        let client = SessionRuntimeClient(endpoint: try SessionRuntimeEndpoint(url: url, generation: generation, token: token))
        try await client.handshake()
        #expect(client.supportsSessionContent)
        guard case .chatPage(let page) = try await client.content(tail) else {
            Issue.record("Client did not decode the chat page")
            return
        }
        #expect(page.transcriptRevision == 7)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            try await client.content(old)
        }
        await #expect(throws: SessionRuntimeContentError.invalidRequest) {
            try await client.content(invalid)
        }
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func reconnectingToLegacyServiceRejectsSemanticReadsButKeepsRawContentAvailable() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let sessionID = SessionID()
        let executionID = UUID()
        var reads = 0
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: { .init(projects: [], sessions: [], availableAgentKinds: []) },
            content: { request in
                reads += 1
                return .chatPage(.init(sessionID: request.sessionID, executionID: request.executionID,
                    transcriptRevision: 13, totalCount: 0, startIndex: 0,
                    entries: [], olderCursor: nil, turnUsageByItemID: [:]))
            }, supportsChatReadModel: true, command: { _ in .none })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let client = SessionRuntimeClient(endpoint: try .init(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url)))
        let semantic = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID, target: .chatReadTail)
        let raw = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID, target: .chatTail)

        try await client.handshake()
        #expect(client.supportsChatReadModel)
        _ = try await client.content(semantic)
        let legacy = try JSONDecoder().decode(SessionRuntimeHandshake.self,
            from: Data("{\"protocolVersion\":1,\"generation\":\"\(generation)\",\"supportsSessionContent\":true}".utf8))
        try client.acceptHandshake(legacy)
        await #expect(throws: SessionRuntimeConnectionError.incompatibleProtocol) { try await client.content(semantic) }
        #expect(reads == 1)
        #expect(!client.supportsChatReadModel)
        #expect(client.supportsSessionContent)
        guard case .chatPage(let page) = try await client.content(raw) else {
            Issue.record("Legacy raw content was unavailable")
            return
        }
        #expect(page.transcriptRevision == 13)
        #expect(reads == 2)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func pendingSemanticReadLeavesHandshakeAndInterruptAvailable() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let probe = RuntimePendingTurn()
        let sessionID = SessionID()
        let executionID = UUID()
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: { .init(projects: [], sessions: [], availableAgentKinds: []) },
            content: { request in
                await probe.start()
                return .chatPage(.init(sessionID: request.sessionID, executionID: request.executionID,
                    transcriptRevision: 17, totalCount: 0, startIndex: 0,
                    entries: [], olderCursor: nil, turnUsageByItemID: [:]))
            }, supportsChatReadModel: true, command: { command in
                if case .session(_, _, .interrupt) = command { probe.interrupt() }
                return .none
            })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let client = SessionRuntimeClient(endpoint: endpoint)
        try await client.handshake()
        let reading = Task { try await client.content(.init(sessionID: sessionID,
            executionID: executionID, target: .chatReadTail)) }
        var entered = probe.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            probe.release()
        }
        defer { watchdog.cancel(); probe.release() }

        try await SessionRuntimeClient(endpoint: endpoint).handshake()
        _ = try await client.command(.session(sessionID, executionID, .interrupt))
        guard case .chatPage(let page) = try await reading.value else {
            Issue.record("Pending semantic read failed")
            return
        }
        #expect(page.transcriptRevision == 17)
        #expect(probe.interruptedWhilePending)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func ptyContentCanExceedChatPageLimitWithoutUsingFullDashboardSnapshot() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let sessionID = SessionID()
        let executionID = UUID()
        let overview = SessionRuntimeSessionOverview(id: sessionID, startedAt: .distantPast,
            agentRef: .builtin(.claudeCode), workingDirectory: "/work",
            executionID: executionID, title: "Terminal", projectID: nil,
            parentSessionID: nil, launchContext: .interactive,
            status: .idle, displayStatus: .idle,
            statusEnteredAt: nil, displayStatusEnteredAt: nil,
            hasUnseenCompletion: false, lastOutputAt: nil, lastTurnCompletedAt: nil,
            kind: .pty(.init(completedTurnSeq: 3, hasProducedOutput: true,
                isRestored: true, isReadyForInput: true, displayRevision: 17)))
        let projected = try SessionViewModel(projection: overview) { _, _ in .none }
        var largePTY = try projected.makeRuntimeSnapshot()
        largePTY.nativeSessionID = String(repeating: "x", count: 5 * 1024 * 1024)
        let largeResponse = largePTY
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: { throw SessionRuntimeConnectionError.rejected("Full snapshot must not run") },
            content: { _ in .ptySnapshot(snapshot: largeResponse, displayRevision: 17) }, command: { _ in .none })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let token = try SessionRuntimeCredentialStore.load(storeURL: fixture.url)
        let request = SessionRuntimeContentRequest(sessionID: sessionID, executionID: executionID,
            target: .ptySnapshot(displayRevision: 17))

        let response = try await runtimeHTTPContent(url: url, token: token,
            generation: generation, request: request)

        #expect(response.status == 200)
        #expect(response.data.count > SessionRuntimeContentLimits.maximumResponseBytes)
        #expect(response.data.count < SessionRuntimeTransport.maximumSnapshotBytes)
        guard case .ptySnapshot(_, let capturedRevision) = try JSONDecoder().decode(
            SessionRuntimeContentResponse.self, from: response.data) else {
            Issue.record("PTY content response was not decoded")
            return
        }
        #expect(capturedRevision == 17)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func largeCommandAndReplyUseTheirOwnLimits() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let response = Data(repeating: 7, count: 66 * 1024 * 1024)
        let transport = try SessionRuntimeTransport(
            generation: generation,
            storeURL: fixture.url,
            snapshot: { throw SessionRuntimeConnectionError.rejected("このテストでは利用しません。") },
            command: { _ in throw SessionRuntimeConnectionError.rejected("このテストでは利用しません。") },
            applicationCommand: { payload in
                #expect(payload.count == 25 * 1024 * 1024)
                return response
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let token = try SessionRuntimeCredentialStore.load(storeURL: fixture.url)
        let client = SessionRuntimeClient(endpoint: try SessionRuntimeEndpoint(url: url, generation: generation, token: token))
        let received = try await client.applicationCommand(Data(repeating: 3, count: 25 * 1024 * 1024))
        #expect(received == response)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test func duplicateConcurrentCommandRunsOnce() async throws {
        let ledger = SessionRuntimeCommandLedger(generation: UUID())
        let request = SessionRuntimeOperation(generation: ledger.generation, payload: Data("first".utf8))
        let counter = RuntimeCommandCounter()
        async let first = ledger.perform(request) { await counter.increment() }
        async let second = ledger.perform(request) { await counter.increment() }
        let results = try await [first, second]
        #expect(results[0] == results[1])
        #expect(await counter.value == 1)
    }

    @Test func sameIdentifierWithDifferentCommandIsRejected() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let request = SessionRuntimeOperation(generation: generation, payload: Data([1]))
        _ = try await ledger.perform(request) { Data([4]) }
        let changed = SessionRuntimeOperation(id: request.id, generation: generation, issuedAt: request.issuedAt, payload: Data([2]))
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(changed) { Data([5]) }
        }
    }

    @Test func expiredOperationCannotExecuteAgainAfterCachePruning() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let now = Date()
        let request = SessionRuntimeOperation(generation: generation, issuedAt: now, payload: Data([1]))
        _ = try await ledger.perform(request, now: now) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(request, now: now.addingTimeInterval(121)) { Data([5]) }
        }
    }

    @Test func fullLedgerRejectsNewCommandWithoutEvictingLiveResult() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumOperations: 1)
        let request = SessionRuntimeOperation(generation: generation, payload: Data([1]))
        _ = try await ledger.perform(request) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data([2]))) { Data([5]) }
        }
        let replay = try await ledger.perform(request) { Data([6]) }
        #expect(replay == Data([4]))
    }

    @Test func wrongGenerationNeverExecutes() async throws {
        let ledger = SessionRuntimeCommandLedger(generation: UUID())
        let counter = RuntimeCommandCounter()
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: UUID(), payload: Data())) {
                await counter.increment()
            }
        }
        #expect(await counter.value == 0)
    }

    @Test func backwardsClockCannotReviveExpiredOperation() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let start = Date()
        let first = SessionRuntimeOperation(generation: generation, issuedAt: start, payload: Data([1]))
        _ = try await ledger.perform(first, now: start) { Data([2]) }
        let later = start.addingTimeInterval(121)
        _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, issuedAt: later, payload: Data([3])), now: later) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(first, now: start) { Data([5]) }
        }
    }

    @Test func desktopAuthenticationDoesNotAcceptChildCredential() {
        let authorization = SessionRuntimeAuthorization(token: "desktop-secret")
        #expect(authorization.accepts("Bearer desktop-secret"))
        #expect(!authorization.accepts("Bearer child-secret"))
        #expect(!authorization.accepts(nil))
        #expect(!authorization.accepts("desktop-secret"))
    }

    @Test func endpointRejectsNonLoopbackAndCredentialsInURL() {
        #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try SessionRuntimeEndpoint(url: URL(string: "http://localhost:8000")!, generation: UUID(), token: "secret")
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try SessionRuntimeEndpoint(url: URL(string: "http://user@127.0.0.1:8000")!, generation: UUID(), token: "secret")
        }
    }

    @Test @MainActor func liveHostWithoutDiscoveryNeverLaunchesDuplicate() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        var launches = 0
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await launcher.connect() }
        #expect(launches == 0)
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func readinessFailureDoesNotSpawnAgainOnNextConnectionAttempt() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        var launches = 0
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await launcher.connect() }
        let next = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await next.connect() }
        #expect(launches == 1)
    }

    @Test func credentialIsPrivateAndRejectsSymlink() throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let token = try SessionRuntimeCredentialStore.loadOrCreate(storeURL: fixture.url)
        #expect(token.count == 64)
        #expect(try SessionRuntimeCredentialStore.load(storeURL: fixture.url) == token)
        let tokenURL = lease.directoryURL.appendingPathComponent("master-token")
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try FileManager.default.removeItem(at: tokenURL)
        let target = fixture.url.appendingPathComponent("foreign-token")
        try Data(token.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: tokenURL, withDestinationURL: target)
        #expect(throws: (any Error).self) { _ = try SessionRuntimeCredentialStore.load(storeURL: fixture.url) }
    }
}

private actor RuntimeCommandCounter {
    var value = 0
    func increment() async -> Data {
        value += 1
        await Task.yield()
        return Data([UInt8(value)])
    }
}

private func runtimeHTTPCommand(_ operation: SessionRuntimeOperation, endpoint: SessionRuntimeEndpoint) async throws -> Data {
    var request = URLRequest(url: endpoint.url.appendingPathComponent("command"), timeoutInterval: 5)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(operation)
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    request.setValue(String(SessionRuntimeEndpoint.protocolVersion), forHTTPHeaderField: "X-Phlox-Runtime-Protocol")
    request.setValue(endpoint.generation.uuidString, forHTTPHeaderField: "X-Phlox-Runtime-Generation")
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 503, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)); continue }
        #expect(status == 200)
        return data
    }
}

private func runtimeHTTPOverview(url: URL, token: String, generation: UUID) async throws -> (status: Int, data: Data) {
    var request = URLRequest(url: url.appendingPathComponent("overview"), timeoutInterval: 5)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(String(SessionRuntimeEndpoint.protocolVersion), forHTTPHeaderField: "X-Phlox-Runtime-Protocol")
    request.setValue(generation.uuidString, forHTTPHeaderField: "X-Phlox-Runtime-Generation")
    let (data, response) = try await URLSession.shared.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
}

private func runtimeHTTPContent(url: URL, token: String, generation: UUID,
                                request: SessionRuntimeContentRequest) async throws -> (status: Int, data: Data) {
    try await runtimeHTTPContent(url: url, token: token, generation: generation,
        encodedRequest: JSONEncoder().encode(request).base64EncodedString())
}

private func runtimeHTTPContent(url: URL, token: String, generation: UUID,
                                encodedRequest: String) async throws -> (status: Int, data: Data) {
    var request = URLRequest(url: url.appendingPathComponent("session-content"), timeoutInterval: 5)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(String(SessionRuntimeEndpoint.protocolVersion), forHTTPHeaderField: "X-Phlox-Runtime-Protocol")
    request.setValue(generation.uuidString, forHTTPHeaderField: "X-Phlox-Runtime-Generation")
    request.setValue(encodedRequest, forHTTPHeaderField: "X-Phlox-Runtime-Content-Request")
    let (data, response) = try await URLSession.shared.data(for: request)
    return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
}

private actor RuntimeKeyRecorder {
    var input = Data()
    func append(_ data: Data) -> Data { input.append(data); return Data() }
}

private actor RuntimeHeldCommands {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    private var waiters: [CheckedContinuation<Data, Never>] = []
    private var released = false
    func wait() async -> Data {
        guard !released else { return Data() }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            entered.continuation.yield(())
        }
    }
    func release() {
        released = true
        for waiter in waiters { waiter.resume(returning: Data()) }
        waiters.removeAll()
    }
}

@MainActor private final class RuntimePendingTurn {
    let entered = AsyncStream<Void>.makeStream()
    var continuation: CheckedContinuation<Void, Never>?
    var starts = 0
    var snapshotsWhilePending = 0
    var completed = false
    var interruptedWhilePending = false
    func start() async {
        starts += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.continuation.yield(())
        }
        completed = true
    }
    func interrupt() {
        interruptedWhilePending = !completed
        release()
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class SaturatedSnapshotDecodeGate: @unchecked Sendable {
    let started = AsyncStream<Void>.makeStream()
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var released = false

    var isReleased: Bool { lock.withLock { released } }

    func decode(_ data: Data) throws -> SessionRuntimeSnapshotEnvelope {
        let snapshot = try JSONDecoder().decode(SessionRuntimeSnapshotEnvelope.self, from: data)
        waitIfNeeded(sequence: snapshot.sequence)
        return snapshot
    }

    func decodeUpdate(_ data: Data) throws -> SessionRuntimeSnapshotUpdate {
        let update = try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: data)
        waitIfNeeded(sequence: update.sequence)
        return update
    }

    private func waitIfNeeded(sequence: UInt64) {
        if sequence <= 2 {
            started.continuation.yield()
            semaphore.wait()
        }
    }

    func release() {
        lock.withLock { released = true }
        semaphore.signal()
        semaphore.signal()
    }
}

private final class SnapshotDecodeGate: @unchecked Sendable {
    enum Failure: Error { case invalid }
    let started = AsyncStream<UInt64>.makeStream()
    let first = DispatchSemaphore(value: 0)
    let fourth = DispatchSemaphore(value: 0)

    func decode(_ data: Data) throws -> SessionRuntimeSnapshotEnvelope {
        let snapshot = try JSONDecoder().decode(SessionRuntimeSnapshotEnvelope.self, from: data)
        if snapshot.sequence == 1 {
            started.continuation.yield(snapshot.sequence)
            first.wait()
        } else if snapshot.sequence == 4 {
            started.continuation.yield(snapshot.sequence)
            fourth.wait()
        } else if snapshot.sequence == 5 {
            throw Failure.invalid
        }
        return snapshot
    }

    func releaseAll() {
        first.signal()
        fourth.signal()
    }
}

private struct RuntimeTransportFixture {
    let url: URL
    init() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        url = root.appendingPathComponent(".verification/runtime-desktop-transport/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("SessionRuntimeTransportTests専用。PID: \(ProcessInfo.processInfo.processIdentifier)、実行: \(ProcessInfo.processInfo.arguments.first ?? "test-runner")。出力: \(url.path)。終了時に削除。\n".utf8).write(to: url.appendingPathComponent("ownership.txt"))
    }
    func remove() {
        do { try FileManager.default.removeItem(at: url) }
        catch { Issue.record("専用fixtureの片付けに失敗しました。\(error)") }
    }
}
