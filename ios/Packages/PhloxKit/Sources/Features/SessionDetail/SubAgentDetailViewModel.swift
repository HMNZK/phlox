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

    /// SwiftUI に渡す、切り詰め済みの本文。
    public struct RenderedBody: Equatable {
        public let head: String
        public let tail: String
        public let omittedBytes: Int
    }

    /// 表示用の本文を UTF-8 バイト数で切り詰める。先頭と末尾をほぼ半分ずつ残すことで、
    /// 実行の文脈と稼働中サブエージェントの最新出力のどちらも確認できるようにする。
    /// `Character` 単位で進めるため、マルチバイト文字や書記素クラスタの途中で切断しない。
    nonisolated public static func renderedBody(_ text: String) -> RenderedBody {
        let originalBytes = text.utf8.count
        guard originalBytes > maxRenderedBytesPerMessage else {
            return RenderedBody(head: text, tail: "", omittedBytes: 0)
        }

        let headLimit = maxRenderedBytesPerMessage / 2
        var headBytes = 0
        var headEnd = text.startIndex
        while headEnd < text.endIndex {
            let nextIndex = text.index(after: headEnd)
            let characterBytes = text[headEnd..<nextIndex].utf8.count
            guard headBytes + characterBytes <= headLimit else { break }
            headBytes += characterBytes
            headEnd = nextIndex
        }

        var tailBytes = 0
        var tailStart = text.endIndex
        let tailLimit = maxRenderedBytesPerMessage - headBytes
        while tailStart > headEnd {
            let previousIndex = text.index(before: tailStart)
            let characterBytes = text[previousIndex..<tailStart].utf8.count
            guard tailBytes + characterBytes <= tailLimit else { break }
            tailBytes += characterBytes
            tailStart = previousIndex
        }

        return RenderedBody(
            head: String(text[..<headEnd]),
            tail: String(text[tailStart...]),
            omittedBytes: originalBytes - headBytes - tailBytes
        )
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
