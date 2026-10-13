import SwiftUI
import AppKit
import UserNotifications
import AgentDomain
import DesignSystem
import SessionFeature

// MARK: - S1 初回起動

/// プロジェクトが 1 件もないときの案内（08 S1）。初回は検出結果と通知まで、2 回目以降は手順 1 だけ。
struct StartOnboardingView: View {
    let showsAllSteps: Bool
    let onAddFolder: () -> Void

    @Environment(\.locale) private var locale
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if showsAllSteps {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phlox へようこそ")
                            .font(DSFont.emptyTitle)
                            .tracking(-0.3)
                            .foregroundStyle(DSColor.textPrimary)
                        Text("複数のコーディングエージェントを 1 つのウィンドウで動かし、承認と質問にまとめて答えます。始めるには作業フォルダを 1 つ追加してください。")
                            .font(.system(size: 13.5))
                            .lineSpacing(6)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                step(1, title: "プロジェクトを追加") {
                    Text("エージェントはこのフォルダの中で作業します。フォルダ自体を Phlox が移動・削除することはありません。")
                        .font(DSFont.dense)
                        .lineSpacing(4)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onAddFolder) {
                        HStack(spacing: 8) {
                            Text("フォルダを追加…")
                            Text(verbatim: "⌘O").font(DSFont.meta).opacity(0.85)
                        }
                        .font(DSFont.row.weight(.semibold))
                        .foregroundStyle(DSColor.accentOnFill)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(DSColor.accentFill, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if showsAllSteps {
                    step(2, title: "通知（任意）") {
                        HStack(spacing: 10) {
                            Text("承認待ちや完了を、ほかのアプリを使っている間も知らせます。")
                                .font(DSFont.dense)
                                .lineSpacing(4)
                                .foregroundStyle(DSColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            notificationControl
                        }
                    }
                    Text("この画面の内容は、あとから 設定（⌘,）でも変更できます。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            .padding(EdgeInsets(top: 64, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: showsAllSteps) {
            guard showsAllSteps else { return }
            await refreshNotificationStatus()
        }
    }

    private func step<Content: View>(
        _ number: Int,
        title: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // 08 S1: 番号の丸は 20pt。本文は丸の幅＋間隔の 30pt だけ字下げする。
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(DSFont.meta.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 20, height: 20)
                    .background(DSColor.segmentTrack, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(DSFont.sessionTitle)
                    .foregroundStyle(DSColor.textPrimary)
                if let note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DSColor.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private var notificationControl: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Text("許可済み")
                .font(DSFont.dense.weight(.medium))
                .foregroundStyle(DSColor.textSecondary)
        case .denied:
            softButton("システム設定を開く…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
        default:
            softButton("通知を許可…") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private func softButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DSFont.dense)
                .foregroundStyle(DSColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DSColor.border, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func refreshNotificationStatus() async {
        // テストのホスト（バンドル外）では通知センターを使えない。
        guard Bundle.main.bundleIdentifier != nil else { return }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - 起動前の確認（F1・F4）

/// 新規セッションの起動要求。確認のあとに同じ内容で起動し直すために持つ。
struct NewSessionRequest: Equatable {
    let ref: AgentRef
    let projectID: ProjectID
    let backend: SessionBackend
}

/// 起動前・起動失敗時に出す確認（08 F1・F4）。
enum SpawnGuard: Identifiable {
    /// worktree を作れず起動を中止した。
    /// `existingWorktree` は 09 E4「既存の worktree を使う」で使える、このリポジトリの worktree の場所（無ければ nil）。
    case worktreeFailed(NewSessionRequest, agentName: String, log: String, existingWorktree: String?)

    var id: String {
        switch self {
        case .worktreeFailed: "worktreeFailed"
        }
    }
}

enum NewSessionCollisionGate {
    /// worktree の失敗として確認に出す内容。git の出力があればそれを、無ければ理由の文を出す。
    static func worktreeFailureLog(_ error: Error) -> String? {
        guard let error = error as? WorktreeIsolationSpawnError else { return nil }
        if case .worktreeCreationFailed(_, _, let detail) = error, !detail.isEmpty {
            return detail
        }
        return error.localizedDescription
    }

    /// git の出力が「そのブランチは既存の worktree で使われている」と言っていれば、その worktree の場所（09 E4「既存の worktree を使う」）。
    /// 出力から場所を確かめられないとき・その場所がいまこのリポジトリの作業ツリーとして働いていないときは nil（ボタンを出さない）。
    static func existingWorktree(in log: String, repository: URL) async -> String? {
        let pattern = #"(?:already checked out at|already used by worktree at) '([^']+)'"#
        guard let match = log.range(of: pattern, options: .regularExpression) else { return nil }
        let quoted = log[match].split(separator: "'", omittingEmptySubsequences: false)
        guard quoted.count >= 2 else { return nil }
        let path = (String(quoted[quoted.count - 2]) as NSString).expandingTildeInPath
        guard await WorktreeIsolationGit.isWorkingTree(URL(fileURLWithPath: path, isDirectory: true), of: repository) else {
            return nil
        }
        return path
    }
}

struct SpawnGuardSheet: View {
    let spawnGuard: SpawnGuard
    let onCancel: () -> Void
    /// 起動する。true = worktree で分ける、false = 分けない。
    let onLaunch: (Bool) -> Void
    /// 既存の worktree（パス）で起動する。
    let onUseWorktree: (String) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        switch spawnGuard {
        case .worktreeFailed(_, _, let log, let existingWorktree):
            // 09 E4: お知らせの型。「閉じる」が既定、次の手の「隔離なしで起動」を先に置く。
            DSDialog(
                .notice,
                title: title,
                message: message,
                buttons: [DSDialogButton("隔離なしで起動") { onLaunch(false) }]
                    + (existingWorktree.map { path in
                        [DSDialogButton("既存の worktree を使う") { onUseWorktree(path) }]
                    } ?? [])
                    + [DSDialogButton("閉じる", role: .primary, action: onCancel)],
                onCancel: onCancel
            ) {
                DSDialogLog(log)
            }
        }
    }

    private var title: String {
        switch spawnGuard {
        case .worktreeFailed:
            AppLocalizedString.string("worktree を作成できなかったため、起動を中止しました", locale: locale)
        }
    }

    private var message: String {
        switch spawnGuard {
        case .worktreeFailed(_, let agentName, _, _):
            String(format: AppLocalizedString.string("%@ の新しいセッションは起動していません。", locale: locale), agentName)
        }
    }

}
