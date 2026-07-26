import SwiftUI
import PhloxCore

/// サブエージェント詳細（task-10）。行タップで解決した subAgentID の会話を
/// `api.subAgentMessages(...)` で取得し、task-8 と同じチャット描画で表示・ポーリング追従する。
@MainActor
@Observable
public final class SubAgentDetailViewModel {
    private let api: PhloxAPI
    public let session: Session
    public let subAgentID: String
    public private(set) var chatMessages: [ChatMessage] = []
    public private(set) var loadError: String?
    private var transcriptWindow = TranscriptWindow()
    public private(set) var isInitialLoading = true

    public static var visibleMessageLimit: Int { TranscriptWindow.defaultLimit }

    /// 1 メッセージについて SwiftUI に渡す本文の UTF-8 バイト数の上限。
    nonisolated public static var maxRenderedBytesPerMessage: Int { 16 * 1024 }

    /// 表示用の本文を UTF-8 バイト数で切り詰める。`Character` 単位で進めるため、
    /// マルチバイト文字や書記素クラスタの途中で切断しない。
    nonisolated public static func renderedBody(_ text: String) -> (text: String, omittedBytes: Int) {
        let originalBytes = text.utf8.count
        guard originalBytes > maxRenderedBytesPerMessage else {
            return (text, 0)
        }

        var retainedBytes = 0
        var endIndex = text.startIndex
        while endIndex < text.endIndex {
            let nextIndex = text.index(after: endIndex)
            let characterBytes = text[endIndex..<nextIndex].utf8.count
            guard retainedBytes + characterBytes <= maxRenderedBytesPerMessage else { break }
            retainedBytes += characterBytes
            endIndex = nextIndex
        }
        return (String(text[..<endIndex]), originalBytes - retainedBytes)
    }

    public init(session: Session, subAgentID: String, api: PhloxAPI) {
        self.session = session
        self.subAgentID = subAgentID
        self.api = api
    }

    public var visibleMessages: [ChatMessage] {
        let messages = chatMessages.filter(SessionDetailViewModel.isVisible)
        let range = transcriptWindow.visibleRange(totalCount: messages.count)
        return Array(messages[range.startIndex...])
    }

    public var hiddenMessageCount: Int {
        let messages = chatMessages.filter(SessionDetailViewModel.isVisible)
        return transcriptWindow.visibleRange(totalCount: messages.count).hiddenCount
    }

    public func expandVisibleWindow() {
        transcriptWindow.expand()
    }

    /// api.subAgentMessages を取得して chatMessages に反映する。
    public func load() async {
        defer { isInitialLoading = false }
        do {
            let messages = try await api.subAgentMessages(sessionID: session.id, subAgentID: subAgentID)
            chatMessages = messages
            loadError = nil
        } catch let error as PhloxError {
            loadError = error.presentation.message
        } catch {
            loadError = "メッセージの取得に失敗しました"
        }
    }

    public static let pollInterval: Duration = .seconds(3)

    /// 詳細表示中のポーリング。画面離脱（`.task` キャンセル）で停止する。
    public func startPolling(interval: Duration = pollInterval) async {
        await load()
        while !Task.isCancelled {
            do { try await Task.sleep(for: interval) } catch { break }
            // sleep 復帰後～refresh の間にキャンセルされた場合、余分な取得を1回もしない
            // （画面離脱相当のキャンセル後は追加取得しない契約。ループ先頭の判定だけでは
            //  sleep 正常復帰直後のキャンセルを取りこぼし flaky になる）。
            if Task.isCancelled { break }
            await refresh()
        }
    }

    /// ポーリング更新。一時的な失敗では表示を消さない。
    public func refresh() async {
        guard let messages = try? await api.subAgentMessages(sessionID: session.id, subAgentID: subAgentID) else {
            return
        }
        if chatMessages != messages {
            chatMessages = messages
        }
        loadError = nil
    }
}
