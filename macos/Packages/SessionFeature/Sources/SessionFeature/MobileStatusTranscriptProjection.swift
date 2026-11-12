import AgentDomain
import Foundation
import StructuredChatKit

/// 組み立て・帰属・文言・開閉は Mac の実装に委ね、本文を ID へ写すだけにする。
enum MobileStatusTranscriptProjection {
    static func build(items: [ChatItem], agent: AgentKind, liveState: AgentStatusLiveState,
                      locale: Locale) -> MobileStatusTranscript? {
        guard AgentStatusCardRouting.usesStatusCard(agent) else { return nil }
        let blocks = AgentStatusCardBuilder.build(items: items, liveState: liveState).map { block in
            switch block {
            case .single(let item):
                return MobileStatusTranscript.Block.messages(ids: [item.id])
            case .commandGroup(_, let items):
                return .messages(ids: items.map(\.id))
            case .statusCard(let card):
                return .card(.init(id: card.id,
                    state: state(card.header.resolvedState(assessment: liveState.hangAssessment)),
                    title: card.header.title(locale: locale), startedAt: card.header.startedAt,
                    endedAt: card.header.endedAt, activityState: card.header.orbState,
                    silence: card.header.isLive ? liveState.hangAssessment?.silence ?? card.header.silence : nil,
                    rows: card.rows.map { row in
                        let kind: MobileStatusTranscript.RowKind
                        let rowState: MobileStatusTranscript.RowState
                        let start: Date?
                        let end: Date?
                        switch row {
                        case .task(let task):
                            kind = .task
                            rowState = state(task.state)
                            start = task.startedAt
                            end = task.endedAt
                        case .outside(let group):
                            kind = .outside
                            rowState = state(group.state)
                            start = nil
                            end = nil
                        }
                        return .init(id: row.id, kind: kind, title: row.title(locale: locale), state: rowState,
                            autoExpanded: AgentStatusCardDisclosure.isAutoExpanded(row, in: card),
                            startedAt: start, endedAt: end, entries: row.entries.map { entry in
                                switch entry {
                                case .item(let item): .message(id: item.id)
                                case .action(let action): .action(.init(id: action.id,
                                    title: action.text(locale: locale), state: workState(action.state),
                                    startedAt: action.startedAt, duration: action.duration,
                                    messageIDs: action.items.map(\.id), symbolName: action.label.symbolName))
                                }
                            })
                    }))
            }
        }
        return MobileStatusTranscript(blocks: blocks)
    }

    private static func state(_ state: AgentStatusHeader.State) -> MobileStatusTranscript.CardState {
        switch state {
        case .running: .running
        case .stalled: .stalled
        case .awaitingReply: .awaitingReply
        case .completed: .completed
        case .interrupted: .interrupted
        case .error: .error
        case .superseded: .superseded
        case .ended: .ended
        }
    }

    private static func state(_ state: AgentStatusTask.State) -> MobileStatusTranscript.RowState {
        switch state {
        case .pending: .pending
        case .inProgress: .inProgress
        case .completed: .completed
        case .interrupted: .interrupted
        }
    }

    private static func state(_ state: AgentStatusWorkState) -> MobileStatusTranscript.RowState {
        switch state {
        case .running: .running
        case .completed: .completed
        case .interrupted: .interrupted
        case .failed: .failed
        case .unknown: .unknown
        }
    }

    private static func workState(_ state: AgentStatusWorkState) -> MobileStatusTranscript.WorkState {
        switch state {
        case .running: .running
        case .completed: .completed
        case .interrupted: .interrupted
        case .failed: .failed
        case .unknown: .unknown
        }
    }
}

extension ChatSessionViewModel {
    public func mobileStatusTranscript(locale: Locale = .current, now: Date = Date()) -> MobileStatusTranscript? {
        let agent = agentRef.builtinKind
        var live = statusCardLiveState
        live.hangAssessment = hangAssessment(now: now)
        return MobileStatusTranscriptProjection.build(items: transcript, agent: agent, liveState: live, locale: locale)
    }
}
