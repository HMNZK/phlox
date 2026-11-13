import Darwin
import Foundation
import AgentDomain
import SessionFeature
import StructuredChatKit

/// 確定点を作ったチャット1件分（ADR 0233）。
public struct DashboardHandoverEntry: Sendable {
    public let sessionID: SessionID
    public let agent: String
    public let preparation: HandoverPreparation
}

/// 計画的なホスト更新のうち、セッション側の手順（ゲート・確定点・取り消し・コミット）。
extension DashboardViewModel {
    private var handoverChats: [ChatSessionViewModel] {
        sessionNodes.compactMap { node -> ChatSessionViewModel? in
            if case .appServer(let chat) = node { return chat }
            return nil
        }
    }

    /// 新しい起動（セッション作成・復元）を止める／再開する。止めている間は休止も行わない。
    public func closeHandoverGate() { handoverGate?.close() }

    /// 門を閉じ、閉じる前に始まったholderの起動が終わるのを待つ（期限あり）。偽なら起動が残っているので更新を中止する。
    public func closeHandoverGateAndDrain(timeout: Duration = .seconds(20)) async -> Bool {
        guard let handoverGate else { return true }
        return await handoverGate.closeAndDrain(timeout: timeout)
    }
    public func openHandoverGate() { handoverGate?.open() }

    /// 更新を延期すべき理由（空なら可）。何も変えない。
    public func handoverDeferralReasons() async -> [String] {
        guard !isRuntimeProjection else { return ["画面側の投影です"] }
        var reasons: [String] = []
        for node in sessionNodes {
            switch node {
            case .pty(let pty):
                // 端末の実行は子の親を引き継げない。動いているものがあれば止めずに延期する。
                switch pty.status {
                case .completed, .error: break
                default: reasons.append("端末セッション「\(pty.displayName)」が動いています")
                }
            case .appServer(let chat):
                // 前回の引き継ぎに失敗して子が生きたまま残るもの。新しい確定点で項目を失うので、更新を延期する。
                if handoverRecoveryNeededSessionIDs.contains(chat.id) {
                    reasons.append("「\(chat.displayName)」は前回の引き継ぎに失敗して復旧待ちです")
                    continue
                }
                if chat.processExit != nil || chat.launchFailure != nil { continue }
                guard chat.isHandoverParticipant else {
                    // 未対応の方式（Codex・Cursor等）が動いていれば、止めずに更新を延期する。
                    reasons.append("「\(chat.displayName)」は実行の引き継ぎに未対応です")
                    continue
                }
                // 子が既に終了している（中断でCLIが終わった等）。引き継ぐ実行が無いので延期理由にしない。
                if await chat.handoverParticipation() == .childEnded { continue }
                if let reason = await chat.handoverGateReason() {
                    reasons.append("「\(chat.displayName)」: \(reason)")
                }
            }
        }
        return reasons
    }

    /// 全チャットの確定点を作る。1つでも失敗したら、作った分を全て再開してから投げる（何も変えない）。
    public func prepareHandoverEntries() async throws -> [DashboardHandoverEntry] {
        var entries: [DashboardHandoverEntry] = []
        var prepared: [ChatSessionViewModel] = []
        for chat in handoverChats where chat.processExit == nil && chat.launchFailure == nil {
            guard chat.isHandoverParticipant else { continue }
            if await chat.handoverParticipation() == .childEnded { continue }
            do {
                let preparation = try await chat.prepareHandover()
                prepared.append(chat)
                entries.append(DashboardHandoverEntry(
                    sessionID: chat.id, agent: chat.agentRef.id, preparation: preparation))
            } catch {
                for earlier in prepared { await earlier.cancelHandover() }
                throw error
            }
        }
        return entries
    }

    public func cancelHandoverEntries() async {
        for chat in handoverChats where chat.isHandoverParticipant { await chat.cancelHandover() }
    }

    /// 不可逆の確定点。各チャットが書込権を手放す（子もholderも終了しない）。
    public func commitHandoverEntries(_ entries: [DashboardHandoverEntry]) async {
        for entry in entries {
            guard let chat = handoverChats.first(where: { $0.id == entry.sessionID }) else { continue }
            await chat.commitHandover(confirmedThrough: entry.preparation.appliedSeq)
        }
    }

    /// 全セッションの会話ログ・descriptorを永続化し終えるまで待つ。
    public func flushForHandover() async {
        for chat in handoverChats { await chat.flushTranscriptNow() }
    }

    /// 確定点に含まれない、生きたholderがあるか（ゲートを閉じる前に始まった起動との競合の検出）。
    /// あれば、引き継ぎ漏れ（新ホストが知らない子）になるので更新を中止する。
    public func unmanagedHolderSessions(excluding entries: [DashboardHandoverEntry]) -> [String] {
        guard let directory = processHolderRecordDirectory else { return [] }
        let known = Set(entries.map { $0.preparation.holder.holderID })
        return HolderCatalog.records(in: directory)
            .filter { record in
                // 子が既に終了したholderは、引き継ぐ実行が無いので対象外。
                HolderCatalog.isAlive(record) && kill(record.childPID, 0) == 0 && !known.contains(record.holderID)
            }
            .map(\.holderID)
    }
}
