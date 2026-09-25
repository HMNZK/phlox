import Foundation
import UserNotifications
import AppKit
import AgentDomain
import DesignSystem

/// 11 通知: 通知の種類ごとの文言。「待ち」は承認待ち・質問待ちにだけ使う（完了は「作業が完了しました」）。
public enum SessionNotificationText {
    public enum Kind: Equatable, Sendable {
        case completed
        /// 承認を求めている対象（Chat の承認プロンプト）。分からないときは nil。
        case awaitingApproval(prompt: String?)
        /// 質問文。秘密の入力を求める質問は本文に中身を出さない。
        case awaitingQuestion(question: String?, isSecret: Bool)
        case error(message: String)
        /// 実行中のまま 2 分以上反応がない（チャット型のみ）。直近の動作が分からないときは nil。
        case stalled(lastAction: String?)
        /// 設定の「通知テスト」。
        case test

        /// Dock・一覧と同じ「対応待ち」の種類。完了とテストは nil。
        var attentionKind: AttentionKind? {
            switch self {
            case .awaitingApproval: .approval
            case .awaitingQuestion: .question
            case .error: .error
            case .stalled: .stalled
            case .completed, .test: nil
            }
        }
    }

    public static func title(_ kind: Kind, sessionName: String, locale: Locale) -> String {
        let key: String
        switch kind {
        case .completed: key = "作業が完了しました: %@"
        case .awaitingApproval: key = "承認待ち: %@"
        case .awaitingQuestion: key = "質問があります: %@"
        case .error: key = "エラーで止まりました: %@"
        case .stalled: key = "応答がありません: %@"
        case .test: return AppLocalizedString.string("Phlox の通知テスト", locale: locale)
        }
        return String(format: AppLocalizedString.string(key, locale: locale), sessionName)
    }

    public static func subtitle(_ kind: Kind, locale: Locale) -> String {
        kind == .test ? AppLocalizedString.string("設定 > 通知", locale: locale) : ""
    }

    /// セッションの通知のサブタイトル「{プロジェクト} · {エージェント}」。分からない部分は省く。
    public static func subtitle(projectName: String?, agentName: String?) -> String {
        [projectName, agentName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 完了の本文。最後の返答の 1 行目、無ければ「次の指示を待っています。」。
    public static func completedBody(lastReply: String?, locale: Locale) -> String {
        let line = firstLine(lastReply ?? "").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? body(.completed, locale: locale) : line
    }

    /// 同じプロジェクトで 3 件以上たまったときの 1 枚。`items` は新しい順。
    public static func summaryTitle(projectName: String, count: Int, locale: Locale) -> String {
        String(format: AppLocalizedString.string("%@ で %lld 件が対応待ち", locale: locale), projectName, count)
    }

    /// 「承認待ち 2 · 質問待ち 1」。種類の並びは一覧と同じ。
    public static func summarySubtitle(kinds: [AttentionKind], locale: Locale) -> String {
        AttentionKind.allCases.compactMap { kind in
            let n = kinds.filter { $0 == kind }.count
            let state: SessionDisplayState = switch kind {
            case .approval: .approval
            case .question: .question
            case .error: .error
            case .stalled: .stalled
            }
            return n == 0 ? nil : "\(state.localizedLabel(locale: locale)) \(n)"
        }.joined(separator: " · ")
    }

    public static func summaryBody(newestName: String, count: Int, locale: Locale) -> String {
        String(format: AppLocalizedString.string("%@ ほか %lld 件", locale: locale), newestName, count - 1)
    }

    public static func body(_ kind: Kind, locale: Locale) -> String {
        switch kind {
        case .completed: AppLocalizedString.string("次の指示を待っています。", locale: locale)
        case .awaitingApproval(let prompt): prompt ?? ""
        case .awaitingQuestion(let question, let isSecret):
            isSecret ? AppLocalizedString.string("入力を求めています", locale: locale) : question ?? ""
        case .error(let message): firstLine(message)
        case .stalled(let lastAction):
            if let lastAction, !lastAction.isEmpty {
                String(format: AppLocalizedString.string("2 分以上反応がありません。最後の動作: %@", locale: locale), lastAction)
            } else {
                AppLocalizedString.string("2 分以上反応がありません。", locale: locale)
            }
        case .test: AppLocalizedString.string("このように通知されます。", locale: locale)
        }
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// 通知のサブタイトルとまとめに使う、セッションの所属。App が Dashboard から引いて渡す。
public struct SessionNotificationContext: Sendable, Equatable {
    public let projectID: String?
    public let projectName: String?
    public let agentName: String?

    public init(projectID: String?, projectName: String?, agentName: String?) {
        self.projectID = projectID
        self.projectName = projectName
        self.agentName = agentName
    }
}

public enum SessionCompletionNotifier {
    /// 通知の文言を引く表示言語。App が起動時にアプリ内の表示言語の設定を渡す。
    public nonisolated(unsafe) static var locale: () -> Locale = { .autoupdatingCurrent }
    /// セッションの所属。App が起動時に Dashboard から引く関数を渡す。
    @MainActor public static var context: (SessionID) -> SessionNotificationContext? = { _ in nil }
    /// いま見ているセッションか。見ているセッションのことは音も含めて知らせない。App が渡す。
    @MainActor public static var isShowing: (SessionID) -> Bool = { _ in false }
    /// 投稿を 1 本に並べる。まとめの判定が配信済みの一覧を読むので、近い通知どうしが競合しないようにする。
    @MainActor private static var postChain: Task<Void, Never>?

    /// 通知の userInfo のキー。クリック後の移動と、対応後の片付けに使う。
    public static let sessionIDKey = "sessionID"
    public static let categoryIdentifier = "Phlox.session"
    public static let openActionIdentifier = "Phlox.open"
    private static let attentionKindKey = "attentionKind"
    /// まとめの 1 枚が含むセッションの ID（新しい順）。
    private static let summaryItemsKey = "summaryItems"
    private static let summaryIdentifierPrefix = "Phlox.attentionSummary."
    /// 通知済みの対応待ち。まとめるかどうかを、反映の遅れうる配信済みの一覧に頼らずに決める。
    @MainActor private static var attentionBook = AttentionNotificationBook()
    /// このプロセスで出した通知の識別子（セッションごと。対応待ちかどうか付き）。配信済みの一覧に反映される前でも
    /// 識別子で消せるように持つ。
    @MainActor private static var postedIdentifiers: [String: [(identifier: String, isAttention: Bool)]] = [:]
    /// この件数以上たまったら、同じプロジェクトの対応待ちを 1 枚にまとめる。
    static let summaryThreshold = 3

    public static func requestAuthorization() {
        guard canUseUserNotifications else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// ターンの完了（またはエラーでの停止）の通知。`status` が `.error` ならエラーの文言にする。
    /// `lastReply` は最後の返答（完了の本文に 1 行目を出す）。
    @MainActor
    public static func notifyCompleted(sessionID: SessionID, sessionName: String, status: SessionStatus? = nil, lastReply: String? = nil) {
        if case .error(let message) = status {
            post(.error(message: message), sessionID: sessionID, sessionName: sessionName, identifierPrefix: "Phlox.sessionCompletion")
        } else {
            post(.completed, sessionID: sessionID, sessionName: sessionName, lastReply: lastReply, identifierPrefix: "Phlox.sessionCompletion")
        }
    }

    /// 対話プロンプト(質問/承認)や無応答で、対応が要る状態になったときの通知。
    /// 完了(running→idle)とは別系統で、ターン途中の質問でも鳴らすために使う。
    @MainActor
    public static func notifyAwaitingInput(sessionID: SessionID, sessionName: String, kind: SessionNotificationText.Kind = .awaitingApproval(prompt: nil)) {
        post(kind, sessionID: sessionID, sessionName: sessionName, identifierPrefix: "Phlox.sessionAwaiting")
    }

    /// 設定の「通知テスト」。完了と同じ音・バナーの設定に従う。
    @MainActor
    public static func notifyTest() {
        post(.test, sessionID: nil, sessionName: "", identifierPrefix: "Phlox.notificationTest")
    }

    /// 対応が済んだセッションの通知を通知センターから消す。対応待ちの通知（とまとめの 1 枚）は
    /// `attention` に無くなったら、完了の通知は `unseenCompletions` にも無くなったら消す。
    /// まとめの 1 枚は、含むセッションがすべて済んだら消す。
    @MainActor
    /// `includesPreviousLaunch` は、前回の起動で出した通知も配信済みの一覧から探して消すか。起動時のセッション復元が
    /// 済むまでは対応待ちが空に見えるので、まだ有効な通知まで消さないよう false にする。
    public static func removeDelivered(attention: Set<SessionID>, unseenCompletions: Set<SessionID>, includesPreviousLaunch: Bool) {
        let attentionIDs = Set(attention.map(\.description))
        let completionIDs = attentionIDs.union(unseenCompletions.map(\.description))
        let clearedProjects = attentionBook.prune(keeping: attentionIDs)
        var known = clearedProjects.map { summaryIdentifierPrefix + $0 }
        for (sessionID, entries) in postedIdentifiers {
            let kept = entries.filter { ($0.isAttention ? attentionIDs : completionIDs).contains(sessionID) }
            known += entries.filter { entry in !kept.contains { $0.identifier == entry.identifier } }.map(\.identifier)
            postedIdentifiers[sessionID] = kept.isEmpty ? nil : kept
        }
        guard canUseUserNotifications else { return }
        // 投稿と同じ列に並べ、投稿より先に片付けが走って消し漏れることを防ぐ。
        let previous = postChain
        postChain = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            if !known.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: known)
                center.removeDeliveredNotifications(withIdentifiers: known)
            }
            // 前回の起動で出したものは識別子を持っていないので、配信済みの一覧から探す。
            guard includesPreviousLaunch else { return }
            let stale = await center.deliveredNotifications().compactMap { note -> String? in
                let info = note.request.content.userInfo
                if let items = info[summaryItemsKey] as? [String] {
                    // ponytail: 一部だけ済んだまとめは件数を書き換えない（再投稿するとバナーと音が出直すため）。
                    return items.contains(where: attentionIDs.contains) ? nil : note.request.identifier
                }
                guard let id = info[sessionIDKey] as? String else { return nil }
                let isAttention = !((info[attentionKindKey] as? String) ?? "").isEmpty
                return (isAttention ? attentionIDs : completionIDs).contains(id) ? nil : note.request.identifier
            }
            if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
        }
    }

    @MainActor
    private static func post(
        _ kind: SessionNotificationText.Kind,
        sessionID: SessionID?,
        sessionName: String,
        lastReply: String? = nil,
        identifierPrefix: String
    ) {
        guard canUseUserNotifications else { return }
        if let sessionID, isShowing(sessionID) { return }
        let soundEnabled = NotificationSettings.isSoundEnabled()
        let bannerEnabled = NotificationSettings.isBannerEnabled()

        // 完了音（Glass）は完了だけ。短時間に連続する複数通知では macOS が通知の content.sound を抑制する
        // （単発は鳴るが連続は鳴らない）ため、完了は NSSound で直接再生する。対応待ちは通知の既定音。
        let playsGlass = kind == .completed || kind == .test
        if soundEnabled, playsGlass || !bannerEnabled {
            if playsGlass { NSSound(named: "Glass")?.play() } else { NSSound.beep() }
        }

        // バナー通知が無効なら UNUserNotification は出さない（音設定とは独立）。
        guard bannerEnabled else { return }

        let locale = locale()
        let context = sessionID.flatMap { Self.context($0) }
        let content = UNMutableNotificationContent()
        content.title = SessionNotificationText.title(kind, sessionName: sessionName, locale: locale)
        content.subtitle = kind == .test
            ? SessionNotificationText.subtitle(kind, locale: locale)
            : SessionNotificationText.subtitle(projectName: context?.projectName, agentName: context?.agentName)
        content.body = kind == .completed
            ? SessionNotificationText.completedBody(lastReply: lastReply, locale: locale)
            : SessionNotificationText.body(kind, locale: locale)
        content.sound = soundEnabled && !playsGlass ? .default : nil
        if let projectID = context?.projectID { content.threadIdentifier = projectID }
        if let sessionID {
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = [
                sessionIDKey: sessionID.description,
                attentionKindKey: kind.attentionKind?.rawValue ?? "",
            ]
        }
        let openTitle = AppLocalizedString.string("開く", locale: locale)
        let identifier = "\(identifierPrefix).\(UUID().uuidString)"
        var decision = AttentionNotificationBook.Decision.single
        if let sessionID, let attention = kind.attentionKind, let projectID = context?.projectID {
            decision = attentionBook.record(
                .init(sessionID: sessionID.description, kind: attention, name: sessionName),
                projectID: projectID
            )
        }
        if let sessionID {
            postedIdentifiers[sessionID.description, default: []].append((identifier, kind.attentionKind != nil))
        }
        var request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        var replacing: [String] = []
        if case .summary(let items) = decision, let projectID = context?.projectID {
            let summary = UNMutableNotificationContent()
            summary.title = SessionNotificationText.summaryTitle(projectName: context?.projectName ?? "", count: items.count, locale: locale)
            summary.subtitle = SessionNotificationText.summarySubtitle(kinds: items.map(\.kind), locale: locale)
            summary.body = SessionNotificationText.summaryBody(newestName: sessionName, count: items.count, locale: locale)
            summary.sound = content.sound
            summary.threadIdentifier = projectID
            summary.categoryIdentifier = categoryIdentifier
            // 新しい順。クリックでは、このうちまだ対応待ちの最も新しいセッションへ移る。
            summary.userInfo = [summaryItemsKey: items.map(\.sessionID)]
            request = UNNotificationRequest(identifier: summaryIdentifierPrefix + projectID, content: summary, trigger: nil)
            // 同じセッションに何度か出した個別の通知も、すべてまとめに置き換える。
            replacing = items.flatMap { item in
                postedIdentifiers[item.sessionID, default: []].filter(\.isAttention).map(\.identifier)
            }
        }

        let previous = postChain
        postChain = Task {
            await previous?.value
            let center = UNUserNotificationCenter.current()
            center.setNotificationCategories([
                UNNotificationCategory(
                    identifier: categoryIdentifier,
                    actions: [UNNotificationAction(identifier: openActionIdentifier, title: openTitle, options: [.foreground])],
                    intentIdentifiers: []
                ),
            ])
            if !replacing.isEmpty {
                // 個別の通知がまだ配信済みの一覧に反映されていなくても消えるよう、待機中からも消す。
                center.removePendingNotificationRequests(withIdentifiers: replacing)
                center.removeDeliveredNotifications(withIdentifiers: replacing)
            }
            try? await center.add(request)
        }
    }

    /// 通知の userInfo から移動先の候補を引く（新しい順。まとめは含むセッション全部、それ以外は 1 件）。
    public static func sessionIDs(from userInfo: [AnyHashable: Any]) -> [SessionID] {
        let ids = (userInfo[summaryItemsKey] as? [String]) ?? [(userInfo[sessionIDKey] as? String)].compactMap { $0 }
        return ids.compactMap(UUID.init(uuidString:)).map { SessionID(rawValue: $0) }
    }

    private static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

/// プロジェクトごとの、通知済みの対応待ち（新しい順）。同じプロジェクトで 3 件以上になったら 1 枚にまとめ、
/// 一度まとめたプロジェクトは、対応待ちが無くなるまで 1 枚のまま書き換える（まとめと個別が並ばないように）。
struct AttentionNotificationBook {
    struct Item: Equatable {
        let sessionID: String
        let kind: AttentionKind
        let name: String
    }

    enum Decision: Equatable {
        case single
        case summary(items: [Item])
    }

    private(set) var items: [String: [Item]] = [:]
    private var summarized: Set<String> = []

    mutating func record(_ item: Item, projectID: String) -> Decision {
        let list = [item] + items[projectID, default: []].filter { $0.sessionID != item.sessionID }
        items[projectID] = list
        guard list.count >= SessionCompletionNotifier.summaryThreshold || summarized.contains(projectID) else { return .single }
        summarized.insert(projectID)
        return .summary(items: list)
    }

    /// 対応が済んだものを除く。対応待ちが無くなったプロジェクトは、次は個別の通知から数え直す。
    /// まとめていて対応待ちが無くなったプロジェクト（まとめの 1 枚を消す先）を返す。
    @discardableResult
    mutating func prune(keeping attention: Set<String>) -> [String] {
        var cleared: [String] = []
        for (projectID, list) in items {
            let kept = list.filter { attention.contains($0.sessionID) }
            items[projectID] = kept.isEmpty ? nil : kept
            if kept.isEmpty, summarized.remove(projectID) != nil { cleared.append(projectID) }
        }
        return cleared
    }
}
