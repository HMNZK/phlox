import AgentDomain
import DesignSystem
import StructuredChatKit
import SwiftUI
@testable import SessionFeature

// エージェント状態カードの画面外描画の入力（見本 ClaudeDesign/agent-status-card の各画面に合わせた会話ログ）。
// 描画は DesignSnapshotRenderTests.agentStatusCardSnapshots が PHLOX_DESIGN_SNAPSHOTS=1 のときだけ行う。

struct AgentStatusCardSnapshotScene {
    let id: String
    let name: String
    /// 見本の画面（01〜09）。
    let board: String
    let width: CGFloat
    let height: CGFloat
    let light: Bool
    var english = false
    let items: [ChatItem]
    let isProcessing: Bool
    var activity: AgentActivityState = .thinking
    /// 無応答の見出し（見本 06）。
    var hang: ChatHangAssessment?
    var isNarrow = false
    /// 手で開閉した行（行 id）。
    var toggledRows: [String] = []
    /// 最初から開いている作業の行。
    var openActionIDs: Set<String> = []

    var blocks: [ChatTranscriptBlock] {
        AgentStatusCardBuilder.build(items: items, liveState: AgentStatusLiveState(
            isProcessing: isProcessing, activityState: activity, hangAssessment: hang, isAwaitingReply: false
        ))
    }
}

/// 会話の流れ（入力・カード・カードの下の返答）を、本番と同じ部品で並べる。
struct AgentStatusCardSnapshotLog: View {
    let scene: AgentStatusCardSnapshotScene
    private let descriptor = AgentRegistry.descriptor(for: .claudeCode)

    var body: some View {
        VStack(alignment: .leading, spacing: TranscriptTypography.itemGap) {
            ForEach(scene.blocks) { block in
                switch block {
                case .single(let item):
                    ChatItemView(item: item, isRunningCommand: false, agentDescriptor: descriptor)
                case .statusCard(let card):
                    AgentStatusCardView(
                        card: card,
                        agentDescriptor: descriptor,
                        isNarrow: scene.isNarrow,
                        hangAssessment: scene.hang.map { hang in { _ in hang } },
                        disclosure: toggled(card),
                        openActionIDs: scene.openActionIDs
                    )
                case .commandGroup:
                    EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, scene.isNarrow ? TranscriptTypography.transcriptHorizontalInset : 40)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggled(_ card: AgentStatusCard) -> AgentStatusCardDisclosure {
        var disclosure = AgentStatusCardDisclosure()
        for id in scene.toggledRows {
            if let row = card.rows.first(where: { $0.id == id }) { disclosure.toggle(row, in: card) }
        }
        return disclosure
    }
}

enum AgentStatusCardSnapshotFixtures {
    private static func user(_ text: String, at start: Date, end: ChatTurnEnd? = nil) -> ChatItem {
        .userMessage(id: "u1", text: text, timestamp: start, attachments: [], turnEnd: end)
    }

    private static func tasks(_ list: [(String, String, AgentTaskStatus)]) -> [AgentTaskItem] {
        list.map { AgentTaskItem(id: $0.0, title: $0.1, status: $0.2) }
    }

    private static func command(
        _ id: String, _ text: String, _ start: Date, at: TimeInterval, done: TimeInterval? = nil,
        intent: String? = nil, output: String = ""
    ) -> ChatItem {
        .commandExecution(
            id: id, command: text, output: output, timestamp: start.addingTimeInterval(at),
            completedAt: done.map(start.addingTimeInterval), intent: intent
        )
    }

    private static func edit(
        _ id: String, _ path: String, _ start: Date, at: TimeInterval, done: TimeInterval? = nil, diff: String = "@@ -1 +1 @@\n-a\n+b"
    ) -> ChatItem {
        .fileChange(
            id: id, changes: [FilePatchChange(path: path, diff: diff, kind: "edit")],
            timestamp: start.addingTimeInterval(at), completedAt: done.map(start.addingTimeInterval)
        )
    }

    private static func snapshot(_ id: String, _ start: Date, at: TimeInterval, _ list: [(String, String, AgentTaskStatus)]) -> ChatItem {
        .taskList(id: id, tasks: tasks(list), timestamp: start.addingTimeInterval(at))
    }

    private static func say(_ id: String, _ text: String, _ start: Date, at: TimeInterval) -> ChatItem {
        .agentMessage(id: id, text: text, timestamp: start.addingTimeInterval(at))
    }

    // 見本 01・09 の会話（再試行の実装）。
    private static func retryItems(now: Date, elapsed: TimeInterval) -> (start: Date, items: [ChatItem]) {
        let start = now.addingTimeInterval(-elapsed)
        let items: [ChatItem] = [
            user("429 が返ったら指数バックオフ＋ジッターで最大 5 回まで再試行するようにして。Retry-After があればそれを優先して", at: start),
            say("a0", "了解です。今の再試行の有無を確かめてから、4 つに分けて進めます。", start, at: 0.5),
            snapshot("task-list-1", start, at: 1, [
                ("t1", "backoff の純関数を追加", .inProgress), ("t2", "Retry-After を秒数と日付の両方で読む", .pending),
                ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
            ]),
            edit("e0", "/repo/internal/httpclient/backoff.go", start, at: 10, done: 11),
            snapshot("task-list-2", start, at: 32, [
                ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .pending),
                ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
            ]),
            snapshot("task-list-3", start, at: elapsed - 24, [
                ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .inProgress),
                ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
            ]),
            command("c1", "Grep Retry-After", start, at: elapsed - 23, done: elapsed - 22.6, output: "client.go:41\nclient.go:58\nretry_after.go:3\nretry_after.go:9"),
            command("c2", "Read /repo/internal/httpclient/client.go", start, at: elapsed - 22, done: elapsed - 21.5),
            command("c3", "Read /repo/internal/httpclient/retry_after.go", start, at: elapsed - 21.5, done: elapsed - 21.1),
            say("a1", "日付の形式で返るサーバーもあるので、`http.ParseTime` で両方受けます。上限は 30 秒にします。", start, at: elapsed - 20),
            edit("e1", "/repo/internal/httpclient/retry_after.go", start, at: elapsed - 19),
        ]
        return (start, items)
    }

    // 見本 04・09 の会話（README の手順）。
    private static func readmeItems(now: Date) -> [ChatItem] {
        let start = now.addingTimeInterval(-300)
        return [
            user("README のセットアップ手順を、今の Makefile のターゲットに合わせて直して", at: start,
                 end: ChatTurnEnd(outcome: .completed, at: start.addingTimeInterval(13))),
            say("a0", "Makefile を確かめてから README を直します。", start, at: 0.5),
            snapshot("task-list-1", start, at: 1, [("t1", "Makefile のターゲットを確認", .inProgress), ("t2", "README の手順を書き換え", .pending)]),
            command("c1", "Read /repo/Makefile", start, at: 1.5, done: 2),
            snapshot("task-list-2", start, at: 5, [("t1", "Makefile のターゲットを確認", .completed), ("t2", "README の手順を書き換え", .inProgress)]),
            edit("e1", "/repo/README.md", start, at: 6, done: 7),
            snapshot("task-list-3", start, at: 12, [("t1", "Makefile のターゲットを確認", .completed), ("t2", "README の手順を書き換え", .completed)]),
            say("a1", "`make setup` は無くなり、`make deps` と `make db-up` に分かれていたので、README の「はじめに」の手順を 3 行から 4 行に直しました。`make run` の説明は今のままで合っています。\n\nローカルの Postgres を Docker で立てる前提を、手順の先頭に 1 文足しています。", start, at: 12.5),
            .turnCost(id: "cost1", costUSD: 0.04, timestamp: start.addingTimeInterval(13)),
        ]
    }

    static func scenes(now: Date) -> [AgentStatusCardSnapshotScene] {
        var result: [AgentStatusCardSnapshotScene] = []

        // 01 作業中
        let retry = retryItems(now: now, elapsed: 72)
        result.append(.init(id: "01", name: "作業中", board: "01-Main", width: 720, height: 700, light: true, items: retry.items, isProcessing: true))
        result.append(.init(id: "01en", name: "作業中英語", board: "01-Main", width: 720, height: 700, light: true, english: true, items: retry.items, isProcessing: true))

        // 02 タスク登録前
        let before = now.addingTimeInterval(-4)
        result.append(.init(
            id: "02", name: "タスク登録前", board: "02-BeforeTasks", width: 720, height: 220, light: false,
            items: [user("store パッケージのトランザクション境界を見直して、Repository ごとに Tx を受け取る形にして", at: before)],
            isProcessing: true
        ))

        // 03 タスクなし
        let plain = now.addingTimeInterval(-18)
        result.append(.init(
            id: "03", name: "タスクなし", board: "03-NoTasks", width: 720, height: 360, light: true,
            items: [
                user("go.mod の Go を 1.25 に上げて、ビルドが通るか見て", at: plain),
                edit("e1", "/repo/go.mod", plain, at: 2, done: 2.2),
                command("c1", "go mod tidy", plain, at: 3, done: 6.1, intent: "依存関係を整理"),
                command("c2", "go build ./...", plain, at: 7, intent: "ビルドが通るか確認"),
            ],
            isProcessing: true
        ))

        // 04 完了
        result.append(.init(id: "04", name: "完了", board: "04-Done", width: 720, height: 560, light: false, items: readmeItems(now: now), isProcessing: false))

        // 05 中断
        let flaky = now.addingTimeInterval(-300)
        result.append(.init(
            id: "05", name: "中断", board: "05-Interrupted", width: 720, height: 380, light: true,
            items: [
                user("auth.spec.ts のフレークを直して。ログイン後のリダイレクトで落ちることがある", at: flaky,
                     end: ChatTurnEnd(outcome: .interrupted, at: flaky.addingTimeInterval(42))),
                snapshot("task-list-1", flaky, at: 0, [
                    ("t1", "失敗するテストを 20 回まわして特定", .inProgress), ("t2", "storageState の書き込みを待つ", .pending), ("t3", "CI で 3 回連続で通す", .pending),
                ]),
                command("c1", "npx playwright test auth.spec.ts --repeat-each=20", flaky, at: 2, done: 17),
                snapshot("task-list-2", flaky, at: 18, [
                    ("t1", "失敗するテストを 20 回まわして特定", .completed), ("t2", "storageState の書き込みを待つ", .inProgress), ("t3", "CI で 3 回連続で通す", .pending),
                ]),
                edit("e1", "/repo/e2e/auth.spec.ts", flaky, at: 20),
            ],
            isProcessing: false
        ))

        // 06 無応答
        let stalled = now.addingTimeInterval(-112)
        result.append(.init(
            id: "06", name: "無応答", board: "06-Stalled", width: 720, height: 440, light: false,
            items: [
                user("infra-terraform の plan を取って、差分を種類ごとに整理して", at: stalled),
                snapshot("task-list-1", stalled, at: 1, [("t1", "plan を取る", .inProgress), ("t2", "差分を種類ごとにまとめる", .pending)]),
                command("c1", "terraform init -upgrade", stalled, at: 2, done: 8.2),
                command("c2", "terraform plan -out=tfplan -lock-timeout=60s", stalled, at: 9),
            ],
            isProcessing: true, hang: ChatHangAssessment(elapsed: 112, silence: 90, isStalled: true)
        ))

        // 07 手で開いた
        let manual = now.addingTimeInterval(-80)
        result.append(.init(
            id: "07", name: "手で開いた", board: "07-ManualOpen", width: 720, height: 780, light: true,
            items: [
                user("429 が返ったら指数バックオフ＋ジッターで最大 5 回まで再試行するようにして。Retry-After があればそれを優先して", at: manual),
                command("c0", "Read /repo/go.mod", manual, at: 1, done: 1.3),
                command("c0b", "go list ./...", manual, at: 1.5, done: 2.4, intent: "パッケージの一覧を確認"),
                snapshot("task-list-1", manual, at: 3, [
                    ("t1", "backoff の純関数を追加", .inProgress), ("t2", "Retry-After を秒数と日付の両方で読む", .pending),
                    ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
                ]),
                .reasoning(id: "r1", text: "ジッターの扱いを先に決める。", timestamp: manual.addingTimeInterval(4)),
                edit("e1", "/repo/backoff.go", manual, at: 5, done: 5.4),
                edit("e2", "/repo/jitter.go", manual, at: 5.5, done: 5.9),
                edit("e3", "/repo/backoff_test.go", manual, at: 6, done: 6.4),
                say("a1", "ジッターは上限の半分から上限までの一様乱数にしました。`attempt` が大きいときの桁あふれも上限で止めます。", manual, at: 7),
                command("c1", "go vet ./...", manual, at: 8, done: 9.4, intent: "go vet で確認"),
                snapshot("task-list-2", manual, at: 34, [
                    ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .pending),
                    ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
                ]),
                snapshot("task-list-3", manual, at: 48, [
                    ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .inProgress),
                    ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
                ]),
                command("c2", "Grep Retry-After", manual, at: 49, done: 49.4, output: "a.go:1\nb.go:2\nc.go:3\nd.go:4"),
                edit("e4", "/repo/retry_after.go", manual, at: 50),
            ],
            isProcessing: true, toggledRows: ["task-t1"]
        ))

        // 08 作業を開いた
        let open = now.addingTimeInterval(-161)
        let diff = """
        @@ -41,3 +41,11 @@
         func (c *Client) Do(req *http.Request) (*http.Response, error) {
        -\treturn c.hc.Do(req)
        +\tfor attempt := 0; ; attempt++ {
        +\t\tres, err := c.hc.Do(req)
        +\t\tif !retryable(res, err) || attempt == maxRetries {
        +\t\t\treturn res, err
        +\t\t}
        +\t\ttime.Sleep(wait(res, attempt))
        +\t}
         }
        """
        result.append(.init(
            id: "08", name: "作業を開いた", board: "08-WorkOpen", width: 720, height: 900, light: false,
            items: [
                user("429 が返ったら指数バックオフ＋ジッターで最大 5 回まで再試行するようにして。Retry-After があればそれを優先して", at: open),
                snapshot("task-list-1", open, at: 1, [
                    ("t1", "backoff の純関数を追加", .inProgress), ("t2", "Retry-After を秒数と日付の両方で読む", .pending),
                    ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
                ]),
                edit("e0", "/repo/backoff.go", open, at: 5, done: 6),
                snapshot("task-list-2", open, at: 32, [
                    ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .inProgress),
                    ("t3", "Do を包んで 429 と 503 を再試行", .pending), ("t4", "テストを追加して通す", .pending),
                ]),
                edit("e00", "/repo/retry_after.go", open, at: 33, done: 34),
                snapshot("task-list-3", open, at: 70, [
                    ("t1", "backoff の純関数を追加", .completed), ("t2", "Retry-After を秒数と日付の両方で読む", .completed),
                    ("t3", "Do を包んで 429 と 503 を再試行", .inProgress), ("t4", "テストを追加して通す", .pending),
                ]),
                .subAgentMarker(id: "sub1", subagentType: "Explore", description: "呼び出し元の洗い出し", status: .completed),
                edit("e1", "/repo/internal/httpclient/client.go", open, at: 80, done: 80.6, diff: diff),
                command(
                    "c1", "go test ./internal/httpclient/... -run TestRetry -count=1", open, at: 81, done: 85.8,
                    intent: "再試行のテストを実行",
                    output: "=== RUN   TestRetry429_RespectsRetryAfter\n--- PASS: TestRetry429_RespectsRetryAfter (0.31s)\n=== RUN   TestRetry503_Jitter\n--- PASS: TestRetry503_Jitter (0.12s)\nok  \tledger/internal/httpclient\t1.204s"
                ),
                edit("e2", "/repo/internal/httpclient/client_test.go", open, at: 90),
            ],
            isProcessing: true, openActionIDs: ["e1", "c1"]
        ))

        // 09 グリッドの狭い列
        let narrow = retryItems(now: now, elapsed: 72)
        result.append(.init(
            id: "09a", name: "グリッド幅360ライト", board: "09-GridNarrow", width: 360, height: 640, light: true,
            items: narrow.items, isProcessing: true, isNarrow: true
        ))
        result.append(.init(
            id: "09b", name: "グリッド幅360ダーク完了", board: "09-GridNarrow", width: 360, height: 500, light: false,
            items: readmeItems(now: now), isProcessing: false, isNarrow: true
        ))
        return result
    }
}
