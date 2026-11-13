import Foundation
import StructuredChatKit

/// 計画的なホスト更新（ADR 0233）で新ホストへ渡す、Codexクライアントの状態。
/// 3層（`JSONRPCClient`→`CodexAppServerClient`→`CodexStructuredAgentClient`）の状態を1つにまとめる。
/// 運ばないもの: `pendingResumeRollback`（復元の失敗時にだけ使う）、`imageInputWriter`（テスト用）。
/// 画面側の`appServerUserAgent`・Codex設定は、既存の記述子の永続値から戻す（ここには持たない）。
struct CodexHandoverState: Codable, Equatable {
    static let currentVersion = 1

    var stateVersion: Int
    var client: CodexClientHandoverState
    var currentThreadId: String?
    var committedThreadId: String?
    var hasEstablishedThread: Bool
    var threadIdentityGeneration: Int
    var lastThreadStartParams: ThreadStartParams?
    var pendingChildInterrupts: [String: String]
    var nativeImageInputEnabled: Bool
    /// 画像の一時ディレクトリのパス。新ホストが削除の責任を引き継ぐ。
    var materializedImageDirectories: [String]
}

extension CodexStructuredAgentClient {
    /// 引き継ぎ側: 新しい子を作らず、旧ホストの子（holder）へ接続して続きから受け取る準備をする。
    public func prepareAdoption(state: Data, transport: HolderTransport) {
        pendingAdoption = (state, transport)
    }

    /// フェンスが最上層に届いた。ここまでの全イベントが反映済みなので、状態を束ねて待っている`prepareHandover`へ渡す。
    func fencePassed(_ id: UUID) async {
        // この層の状態は、awaitを挟む前に採取する。
        let currentThreadId = self.currentThreadId
        let committedThreadId = self.committedThreadId
        let hasEstablishedThread = self.hasEstablishedThread
        let threadIdentityGeneration = self.threadIdentityGeneration
        let lastThreadStartParams = self.lastThreadStartParams
        let pendingChildInterrupts = self.pendingChildInterrupts
        let nativeImageInputEnabled = self.nativeImageInputEnabled
        let directories = materializedImageDirectories.map(\.path).sorted()
        let clientState = await client.takeFenceState(id)
        let data: Data?
        if let clientState {
            data = try? JSONEncoder().encode(CodexHandoverState(
                stateVersion: CodexHandoverState.currentVersion, client: clientState,
                currentThreadId: currentThreadId, committedThreadId: committedThreadId,
                hasEstablishedThread: hasEstablishedThread, threadIdentityGeneration: threadIdentityGeneration,
                lastThreadStartParams: lastThreadStartParams, pendingChildInterrupts: pendingChildInterrupts,
                nativeImageInputEnabled: nativeImageInputEnabled, materializedImageDirectories: directories))
        } else {
            data = nil
        }
        orderedEventContinuation.yield(.normalized(.handoverFence(id)))
        eventContinuation.yield(.handoverFence(id))
        fenceWaiters.removeValue(forKey: id)?.resume(returning: data)
    }

    private func expireFence(_ id: UUID) {
        fenceWaiters.removeValue(forKey: id)?.resume(returning: nil)
    }

    /// 他のホストに書込権を取られた、またはholderとの接続が切れた。子は終了していないので、起動し直さず復旧待ちにする。
    func handleOwnershipLoss(_ reason: HolderTransport.EndReason) {
        guard !handedOver else { return }
        let event = NormalizedChatEvent.error(
            message: "実行の所有権を失いました(\(reason))。子のプロセスは終了していません。復旧を待っています。")
        orderedEventContinuation.yield(.normalized(event))
        eventContinuation.yield(event)
    }
}

extension CodexStructuredAgentClient: HandoverCapableClient {
    public func handoverGateReason() async -> String? {
        guard let holder = client.holderTransport, holder.holderRecord != nil else {
            return "Codexの子がholder経由ではありません"
        }
        if handedOver { return "既に新ホストへ手放しています" }
        if let reason = holder.endedReason { return "holderとの接続が切れています(\(reason))" }
        if holder.hasUnknownSend { return "結果不明の送信があります" }
        if imageTurnInFlight || modelChangeInFlight { return "画像の送信またはモデルの変更を処理中です" }
        return await client.handoverGateReason()
    }

    public func prepareHandover(fence: UUID) async throws -> HandoverPreparation {
        guard let holder = client.holderTransport, let record = holder.holderRecord else {
            throw HandoverError.notReady("Codexの子がholder経由ではありません")
        }
        if let reason = await handoverGateReason() { throw HandoverError.notReady(reason) }
        // 受信側（JSONRPCClientの受信ループ）が最後の行を処理し終えるまで待つ。待つ間にこのactorへ再入するので、完了後に再確認する。
        guard let applied = await holder.quiesce() else {
            await client.resendUndeliveredResponses()
            throw HandoverError.timedOut
        }
        if let reason = await handoverGateReason() {
            holder.resumeAfterQuiesce()
            await client.resendUndeliveredResponses()
            throw HandoverError.notReady(reason)
        }
        // 受信行は3層の非同期ストリームを通るので、配送の停止だけでは途中に未適用の行が残る。
        // フェンスを先頭から流し、最上層に届いた時点で状態を採取する（期限つき。無期限に待たない）。
        let data: Data? = await withCheckedContinuation { continuation in
            fenceWaiters[fence] = continuation
            Task { await client.beginHandoverFence(fence) }
            Task {
                try? await Task.sleep(for: .seconds(10))
                expireFence(fence)
            }
        }
        guard let data else {
            holder.resumeAfterQuiesce()
            await client.resendUndeliveredResponses()
            throw HandoverError.timedOut
        }
        return HandoverPreparation(holder: record, appliedSeq: applied, clientState: data, fence: fence)
    }

    public func cancelHandover() async {
        client.holderTransport?.resumeAfterQuiesce()
        // 送信が止まっている間に答えられた承認・質問の応答は、確実に未送信なので、ここで送り直す。
        await client.resendUndeliveredResponses()
    }

    public func commitHandover(confirmedThrough: UInt64) async {
        guard let holder = client.holderTransport else { return }
        handedOver = true
        bridgeTask?.cancel()
        bridgeTask = nil
        await client.detachForHandover()
        holder.confirm(through: confirmedThrough)
        holder.releaseForHandover()
    }

    public func completeAdoption() async throws {
        guard let adoption = pendingAdoption else { throw HandoverError.adoptionFailed("引き継ぎの準備がありません") }
        pendingAdoption = nil
        // 子へ接続する前に、状態を読めるか・版が合うかを確かめる（どちらも失敗しても子には何もしない）。
        let state: CodexHandoverState
        do { state = try JSONDecoder().decode(CodexHandoverState.self, from: adoption.state) } catch {
            throw HandoverError.adoptionFailed("クライアント状態を読めません: \(error)")
        }
        guard state.stateVersion == CodexHandoverState.currentVersion else {
            throw HandoverError.adoptionFailed("クライアント状態の版(\(state.stateVersion))に対応していません")
        }
        // 書込権を取って接続する。失敗しても子には何もしない（終了・再生成しない）。
        do { try adoption.transport.start() } catch {
            throw HandoverError.adoptionFailed("holderへ接続できません: \(error)")
        }
        // 反映済みの番号より後の行が欠けていないか。欠けていれば確認（confirm）を送らず、手放すだけにする。
        if let fault = adoption.transport.adoptionContinuityFault() {
            adoption.transport.releaseForHandover()
            throw HandoverError.adoptionFailed(fault)
        }
        guard adoption.transport.unknownSendIDs.isEmpty else {
            adoption.transport.releaseForHandover()
            throw HandoverError.adoptionFailed("旧ホストの結果不明の送信があります。再送しません")
        }
        currentThreadId = state.currentThreadId
        committedThreadId = state.committedThreadId
        hasEstablishedThread = state.hasEstablishedThread
        threadIdentityGeneration = state.threadIdentityGeneration
        lastThreadStartParams = state.lastThreadStartParams
        pendingChildInterrupts = state.pendingChildInterrupts
        nativeImageInputEnabled = state.nativeImageInputEnabled
        materializedImageDirectories = Set(state.materializedImageDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) })
        await client.applyHandoverState(state.client)
        adoption.transport.setOwnershipLossHandler { [weak self] reason in
            Task { await self?.handleOwnershipLoss(reason) }
        }
        // 未応答の承認・質問は、原文を通常の受信経路へ再投入して作り直す（応答は新ホストが同じIDで一度だけ返す）。
        // 受信を始める前に行うので、再投入された要求が、続きの行より先に届く。
        await client.reinjectServerRequests(state.client.rpc.pendingServerRequests)
        await start()
    }
}
