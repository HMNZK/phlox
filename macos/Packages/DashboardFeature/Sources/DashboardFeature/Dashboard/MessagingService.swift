import Foundation
import AgentDomain
import ControlServer
import MessageStore
import PTYKit
import SessionFeature

/// エージェント間メッセージングの送信・レート制限・記録（DashboardViewModel からの Extract Class、R2）。
/// 宛先解決で SessionViewModel（@MainActor）に触れるため @MainActor 必須。
@MainActor
final class MessagingService {
    /// エージェント間通信の暴走防止。1 セッションが 1 秒間に送信できる上限。
    static let maxSendCountPerSecond = 20
    /// 送信レート制限に使うスライディングウィンドウ。
    static let sendRateLimitWindowSeconds: TimeInterval = 1

    private let pty: any PTYManagerProtocol
    private let messages: any MessageStoreProtocol
    private var sendTimestamps: [SessionID: [Date]] = [:]
    /// 送信レート制限の現在時刻シーム。既定は実時計。テストは固定時刻を注入して
    /// スライディングウィンドウを決定論化する（実時計依存の断続的失敗の除去）。
    private let now: @Sendable () -> Date

    init(
        pty: any PTYManagerProtocol,
        messages: any MessageStoreProtocol,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.pty = pty
        self.messages = messages
        self.now = now
    }

    func send(
        to recipient: Recipient,
        text: String,
        submit: Bool,
        from: SessionID?,
        inReplyTo: UUID?,
        images: [ControlImageAttachment],
        sessions: [SessionNode]
    ) async -> DashboardViewModel.SendOutcome {
        if let from {
            let now = self.now()
            let windowStart = now.addingTimeInterval(-Self.sendRateLimitWindowSeconds)
            var timestamps = (sendTimestamps[from] ?? []).filter { $0 > windowStart }
            if timestamps.count >= Self.maxSendCountPerSecond {
                return .rateLimited
            }
            timestamps.append(now)
            sendTimestamps[from] = timestamps
        }

        if containsRejectedControlCharacters(text) {
            return .rejected(reason: "control-characters")
        }

        let matchedNode: SessionNode?
        let resolved: any ControllableSession
        switch recipient {
        case .id(let sid):
            guard let node = sessions.first(where: { $0.id == sid }) else {
                return .notFound
            }
            matchedNode = node
            resolved = node.controllable
        case .name(let name):
            let key = normalizeRecipientKey(name)
            let matches = sessions.filter {
                normalizeRecipientKey($0.controllable.name) == key
                    || normalizeRecipientKey($0.controllable.displayName) == key
            }
            switch matches.count {
            case 0:
                return .notFound
            case 1:
                matchedNode = matches[0]
                resolved = matches[0].controllable
            default:
                return .ambiguous(matches.map(\.id))
            }
        }

        if let from, resolved.id == from {
            return .rejected(reason: "self-send")
        }

        if !images.isEmpty {
            guard let appServer = matchedNode?.appServer else {
                return .imagesUnsupported
            }
            guard appServer.acceptsImageAttachments else {
                return .imagesUnsupported
            }
        }

        let senderName = from.flatMap { id in
            sessions.first(where: { $0.id == id })?.controllable.displayName
        } ?? "external"
        let fromName: String? = senderName == "external" ? nil : senderName

        let payload = fromName.map { "[from \($0)] \(text)" } ?? text

        let deliveryOutcome: DashboardViewModel.SendOutcome
        do {
            if !images.isEmpty, let appServer = matchedNode?.appServer {
                try await appServer.sendTextWithControlImages(
                    payload,
                    submit: submit,
                    images: images.map { (mediaType: $0.mediaType, data: $0.data) }
                )
            } else {
                try await resolved.sendText(payload, submit: submit)
            }
            deliveryOutcome = .sent
        } catch ChatSessionViewModel.ControlImageSendError.imagesUnsupported {
            deliveryOutcome = .imagesUnsupported
        } catch PTYError.sessionNotFound, ControllableSessionError.notSpawned {
            deliveryOutcome = .notSpawned
        } catch {
            deliveryOutcome = .deliveryFailed
        }

        let message = AgentMessage(
            fromSession: from,
            fromName: fromName,
            toSession: resolved.id,
            toName: resolved.displayName,
            text: text,
            submit: submit,
            createdAt: Date(),
            delivered: deliveryOutcome == .sent,
            inReplyTo: inReplyTo
        )
        await messages.record(message)

        return deliveryOutcome
    }

    private func normalizeRecipientKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func containsRejectedControlCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if scalar == "\r" || scalar == "\n" || scalar == "\u{1B}" {
                return true
            }
            if value == 0x7F {
                return true
            }
            if value < 0x20, scalar != "\t" {
                return true
            }
        }
        return false
    }
}
