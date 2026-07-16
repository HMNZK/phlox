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

    public init(session: Session, subAgentID: String, api: PhloxAPI) {
        self.session = session
        self.subAgentID = subAgentID
        self.api = api
    }

    public var visibleMessages: [ChatMessage] {
        chatMessages.filter(SessionDetailViewModel.isVisible)
    }

    /// api.subAgentMessages を取得して chatMessages に反映する。
    public func load() async {
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
