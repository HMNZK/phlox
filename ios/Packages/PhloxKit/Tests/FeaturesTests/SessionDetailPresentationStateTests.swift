import Foundation
import AgentDomain
import DesignSystemIOS
import PhloxCore
import Testing
@testable import Features

@Suite("セッション詳細の表示状態")
struct SessionDetailPresentationStateTests {
    private func state(
        _ status: SessionStatus,
        stalled: Bool = false,
        backend: String = "appServer",
        canInterrupt: Bool = true,
        recovering: Bool = false
    ) -> SessionDetailPresentationState {
        SessionDetailPresentationState(
            session: Session(
                id: "s1", name: "Rose", agent: .claudeCode, status: status,
                backend: backend, isStalled: stalled, updatedAt: Date(timeIntervalSince1970: 0)
            ),
            status: status,
            canInterrupt: canInterrupt,
            hasMessages: true,
            isInitialLoading: false,
            loadError: nil,
            isRecoveringInitialSend: recovering
        )
    }

    @Test("AC-8-17 の全状態で状態語・入力欄・停止・使用量を決める")
    func mapsEveryConversationState() {
        let cases: [(SessionDetailPresentationState, SessionDisplayState?, Bool, Bool, Bool, Bool)] = [
            (state(.running), .running, true, true, true, false),
            (state(.running, stalled: true), .stalled, true, true, true, false),
            (state(.idle), .idle, true, false, true, false),
            (state(.completed(exitCode: 0)), .done, true, false, true, false),
            (state(.completed(exitCode: 1)), .done, true, false, true, false),
            (state(.error(message: "失敗")), .error, true, false, true, false),
            (state(.awaitingApproval(prompt: "確認")), .approval, true, false, true, false),
            (state(.awaitingUserQuestion), .question, true, false, true, false),
            (state(.starting), .starting, false, false, false, true),
            (state(.running, backend: "pty"), nil, false, false, false, false),
        ]

        for (actual, displayState, input, stop, usage, startingBanner) in cases {
            #expect(actual.displayState == displayState)
            #expect(actual.showsInputBar == input)
            #expect(actual.showsStopButton == stop)
            #expect(actual.showsUsage == usage)
            #expect(actual.showsStartingBanner == startingBanner)
        }
    }

    @Test("会話本文は loading・empty・fetchError・messages・unsupported に分ける")
    func mapsTranscriptStates() {
        func transcript(
            backend: String = "appServer",
            hasMessages: Bool = false,
            loading: Bool = false,
            error: String? = nil
        ) -> SessionDetailPresentationState.Transcript {
            SessionDetailPresentationState(
                session: Session(
                    id: "s1", name: "Rose", agent: .claudeCode, status: .idle,
                    backend: backend, updatedAt: Date(timeIntervalSince1970: 0)
                ),
                status: .idle,
                canInterrupt: true,
                hasMessages: hasMessages,
                isInitialLoading: loading,
                loadError: error,
                isRecoveringInitialSend: false
            ).transcript
        }

        #expect(transcript(loading: true) == .loading)
        #expect(transcript() == .empty)
        #expect(transcript(error: "通信失敗") == .fetchError)
        #expect(transcript(hasMessages: true, error: "無視される") == .messages)
        #expect(transcript(backend: "pty", loading: true) == .unsupported)
    }

    @Test("新規チャットの送信復帰中は起動バナーを隠して入力を残す")
    func keepsComposerForRecoveredInitialSend() {
        let actual = state(.starting, recovering: true)

        #expect(!actual.showsStartingBanner)
        #expect(actual.showsInputBar)
        #expect(actual.showsUsage)
    }

    @Test("無応答の時計は Mac と同じ m:ss で、負値は 0:00 に丸める")
    func formatsStallClockLikeMac() {
        #expect(SessionDetailPresentationState.elapsedClock(192) == "3:12")
        #expect(SessionDetailPresentationState.elapsedClock(60) == "1:00")
        #expect(SessionDetailPresentationState.elapsedClock(-1) == "0:00")
    }
}
