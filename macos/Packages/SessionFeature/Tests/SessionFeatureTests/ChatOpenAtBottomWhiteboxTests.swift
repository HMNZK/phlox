import Foundation
import Testing
@testable import SessionFeature

@MainActor
struct ChatOpenAtBottomWhiteboxTests {

    @Test("セッション切替は追従を初期化し、同じセッションの読み戻しは維持する")
    func sessionChangeResetsOnlyTheNewSession() {
        let controller = ChatAutoFollowController()
        controller.userScrollBegan()
        controller.userScrollEnded(isAtBottom: false)

        #expect(controller.contentDidChange() == false)

        controller.sessionDidChange()

        #expect(controller.isFollowing == true)
        #expect(controller.contentDidChange() == true)
    }

    @Test("本文更新は追従中だけ最下部へ寄せる")
    func contentUpdatesScrollOnlyWhileFollowing() {
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .transcript, isFollowing: true))
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .status, isFollowing: true))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .transcript, isFollowing: false))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .status, isFollowing: false))
        // PM 追記: .appear の真理値表が無検査だと、task-3 の目的そのもの（開いたら最下部）が
        // 1行の改変で無検査に壊れる（レビュアーが変異 P7 で実証）。
        #expect(ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .appear, isFollowing: true))
        #expect(!ChatBottomScrollPolicy.shouldScrollToBottom(trigger: .appear, isFollowing: false))
    }

    @Test("遅延した最下部スクロールは追従中かつ最新世代だけ実行する")
    func deferredBottomScrollRequiresFollowingAndCurrentGeneration() {
        #expect(
            ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 3,
                currentGeneration: 3,
                isFollowing: true
            )
        )
        #expect(
            !ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 3,
                currentGeneration: 3,
                isFollowing: false
            )
        )
        #expect(
            !ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                generation: 2,
                currentGeneration: 3,
                isFollowing: true
            )
        )
    }

    @Test("appear と再選択の最下部ジャンプは遅延と世代ガードを使う")
    func openingAndReselectingUseDeferredGenerationGuard() throws {
        let source = try ChatOpenAtBottomWhiteboxSource.text("ChatTranscriptView.swift")
        let sessionChange = try #require(
            source.section(from: ".onChange(of: viewModel.id)", until: ".onAppear")
        )
        let bottomScroll = try #require(
            source.section(from: "private func scrollToBottomIfNeeded", until: "private func scheduleScrollToBottom")
        )

        #expect(sessionChange.contains("autoFollow.sessionDidChange()"))
        #expect(sessionChange.contains("scheduleScrollToBottom(proxy)"))
        #expect(bottomScroll.contains("case .appear:"))
        #expect(bottomScroll.contains("scheduleScrollToBottom(proxy)"))
        // PM 追記: 判定をポリシーへ切り出しても、View がそれを呼び実際の追従状態を渡すことは
        // 別に凍結しないと守られない（ガードを消す変異・isFollowing に true を渡す変異が
        // どちらもテストを素通りしたため）。ScrollViewProxy を要求するので振る舞いでは検証できない。
        #expect(
            bottomScroll.contains("ChatBottomScrollPolicy.shouldScrollToBottom("),
            "View は寄せるかどうかの判定をポリシーへ委ねること"
        )
        #expect(
            bottomScroll.contains("isFollowing: autoFollow.contentDidChange()"),
            "ポリシーへは実際の追従状態を渡すこと（固定値を渡すと読み戻し中も引き戻す）"
        )
        #expect(source.contains("""
        Task { @MainActor in
                    guard ChatBottomScrollPolicy.shouldPerformDeferredScroll(
                        generation: generation,
                        currentGeneration: jumpGeneration,
                        isFollowing: autoFollow.isFollowing
                    ) else { return }
                    proxy.scrollTo(ChatScrollTarget.bottom.rawValue, anchor: .bottom)
                }
        """))
    }
}

private extension String {
    func section(from start: String, until end: String) -> String? {
        guard let startRange = range(of: start), let endRange = range(of: end, range: startRange.upperBound..<endIndex) else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}

private enum ChatOpenAtBottomWhiteboxSource {
    static func text(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SessionFeature/\(relativePath)"),
            encoding: .utf8
        )
    }
}
