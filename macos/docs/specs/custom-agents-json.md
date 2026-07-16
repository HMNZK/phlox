---
status: active
last-verified: 2026-07-08
---

# ユーザー定義CLI (JSON) 対応 設計ゴール (ロードマップ#4 / 低リスク分離型)

- 目的: enum 改修なしで、ユーザーが JSON に任意の対話型 CLI を宣言するだけで Phlox に追加できるようにする(「あらゆる CLI 対応」のインフラ)。
- 方針: **低リスク分離型**。`AgentKind` enum(組込 CLI。設計当時7種・現行は claudeCode/codex/cursor の3種)は維持。カスタム CLI は**文字列 id の別空間**として JSON から `AgentRegistry` に読み込む。#3 のレジストリ基盤の上に積む。
- 完了検知: カスタムは **idle-fallback のみ**(hookKind=none)。調査レポートの結論どおり idle 方式は任意の対話型 CLI に一般化できるため、これで十分。hook 方式は組込CLIのコード定義に限定。
- 担当: 設計・実装は Codex(シニア)にヘッドレス委譲。検証・コミットは ClaudeCode(PM)。
- ブランチ: `feature/ai-cli-integration`。**main マージしない**(コミットまで)。

## 最重要の不変条件(回帰ガード・後方互換)
1. **既存の永続化セッションがバイト互換で復元できる**こと。現状セッションは `AgentKind`(enum rawValue)で保存されている。識別子を `AgentRef` 等へ拡張する場合、**旧フォーマット(裸の AgentKind rawValue)を従来どおりデコードできる**こと。レガシー JSON をデコード→組込として復元できる単体テストを必ず追加して証明する。
2. **カスタム JSON が存在しないとき、挙動は一切変わらない**こと。既存テスト(AgentDomain 41 / DashboardFeature 186)を**変更せず全 pass**。
3. 組込 CLI（設計当時7種・現行は claudeCode/codex/cursor の3種）の `AgentLaunchPlan` はバイト等価で不変(`AgentLaunchPlannerTests` のアサーション unchanged)。
4. サージカル編集。

## 設計指針(Codex が詳細設計してよい)
1. **識別子の拡張**: セッションが参照する agent を `AgentRef`(例: `.builtin(AgentKind)` / `.custom(String)`)に統一。Codable は後方互換に:
   - builtin は**既存 AgentKind と同一表現**でエンコード(旧データと一致)。
   - custom は区別可能な別表現。
   - デコードは「まず AgentKind として解釈、失敗時に custom」等で旧データを救済。
2. **カスタム定義のロード**: ユーザー JSON(既定 `~/.config/phlox/agents.json`、テスト用に URL 注入可能に)から `CustomAgentDefinition` を読み、`AgentDescriptor` 化して registry にマージ。パース失敗・ファイル無しは握りつぶさず「無効エントリを無視して残りを読む/ログ」する(全体を壊さない)。
3. **JSON スキーマ**(例):
   ```json
   {
     "agents": [
       {
         "id": "aider",
         "displayName": "Aider",
         "binaryName": "aider",
         "symbolName": "wrench.and.screwdriver",
         "colorHex": "#E5A53F",
         "baseArgs": [],
         "bypassArgs": ["--yes-always"],
         "bypassEnv": {},
         "statusBootstrap": "idleOnSpawnComplete",
         "resume": { "mode": "flag", "args": ["--restore"] }
       }
     ]
   }
   ```
   - hookKind は受け付けない(常に none=idle)。`resume.mode`: none / flag(args) / namedFlag(args, +uuid)。
   - id は組込 AgentKind rawValue と衝突不可(衝突時はそのエントリを無視+ログ)。
4. **registry/planner/UI の対応**:
   - registry は builtin descriptor(設計当時7・現行3) + custom descriptor(JSON) を id で引けるように。
   - `AgentLaunchPlanner` は custom も descriptor の spec から従来同様に plan を生成。
   - New Session メニュー・サイドバー等は builtin + custom を列挙(PATH 上に binary があるものを露出、組込と同じ検出方針)。
   - bypass: custom は `phlox.bypass.<id>` を既定 true。

## 受け入れ条件
1. `xcodebuild ... build` 成功。
2. `swift test`(AgentDomain / DashboardFeature)が**既存分 unchanged で全 pass**。
3. 追加テスト:
   - レガシー永続化(裸 AgentKind)のデコード→builtin 復元(後方互換証明)。
   - カスタム JSON ロード→descriptor 生成→`AgentLaunchPlan` が宣言どおり(binary/baseArgs/bypassArgs/bypassEnv/idleOnSpawnComplete)。
   - custom セッション ref の Codable ラウンドトリップ。
   - 不正 JSON / id 衝突エントリが無視され、他が読めること。
4. `docs/specs/custom-agents-json.md` 末尾に「カスタム CLI 追加手順(JSON 例つき)」を追記。

## 自己検証 & 報告(Codex)
- build/test を実走し正直に報告。テスト削除・skip・期待値改変での糊塗は禁止。
- runtime(実アプリでのセッション復元・spawn)はこの環境で検証不可。**後方互換は単体テストで証明**し、実機復元はユーザー確認事項として明記する。
- **コミットしない**(PM が検証後に commit)。変更/新規ファイル一覧・build/test 結果・設計判断・残課題を簡潔に報告。

## カスタム CLI 追加手順

1. `~/.config/phlox/agents.json` を作成する。ディレクトリが無い場合は先に `mkdir -p ~/.config/phlox` を実行する。
2. `agents` 配列に CLI 定義を追加する。`id` は組込 CLI 3種の rawValue（`claudeCode` / `codex` / `cursor`。他の CLI は ADR 0041 で削除済み）と衝突できない。
3. `binaryName` が Phlox 起動時の PATH 上で解決できる状態にしてから Phlox を再起動する。解決できたカスタム CLI だけが New Session メニューに表示される。
4. カスタム CLI は hook を使わず、常に `idleOnSpawnComplete` の idle-fallback で完了検知する。`hookKind` は指定しない。

```json
{
  "agents": [
    {
      "id": "aider",
      "displayName": "Aider",
      "binaryName": "aider",
      "symbolName": "wrench.and.screwdriver",
      "colorHex": "#E5A53F",
      "baseArgs": ["--model", "sonnet"],
      "bypassArgs": ["--yes-always"],
      "bypassEnv": {
        "AIDER_AUTO_COMMITS": "0"
      },
      "statusBootstrap": "idleOnSpawnComplete",
      "resume": {
        "mode": "flag",
        "args": ["--restore"]
      }
    }
  ]
}
```

`resume.mode` は次を指定できる。

- `none`: resume 引数を追加しない。
- `flag`: `args` を resume 時にそのまま追加する。
- `namedFlag`: `args` の後ろに Phlox の session UUID を付ける。新規作成時にも同じ UUID を渡し、復元時に同じ値で resume する。
