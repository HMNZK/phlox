---
status: completed
last-verified: 2026-07-20
---

# 0003: モバイル複数行メッセージ送信バグ修正 worklog

実機で発見したバグの診断・修正 run 記録。診断は計装→実機再現→ログで真因確定、修正は PM（Claude）が実装し `persona-reviewer` で独立レビュー、実機 e2e で確認。

## バグ

モバイルから複数行メッセージ（例: AskUserQuestion を求める長文）を新規メッセージで送ると「Mac側で問題が発生しました」というエラーになり送信できない。単一行（例:「test」）は送れる。

## 根本原因（実機ログで確定）

計装ログで `POST /send bodyLen=360 -> 400 {"error":"control-characters"}`、拒否文字が `U+000A,U+000A`（改行 LF が2つ）と確定。`MessagingService.containsRejectedControlCharacters`（macos/DashboardFeature）が本文中の改行 `\n` を拒否文字として弾いていた。配信層 `SessionViewModel.sendText`（macos/SessionFeature）は bracketed paste で複数行を安全に扱い submit は別途 `\r` で行うため、本文中の `\n` は正当であり、事前拒否は過剰だった。

副次原因（診断が難航した理由）: Mac の `ErrorDTO` は理由を `error` キーで返すが、iOS `ServerErrorDTO` は `message`/`reason` だけを読んでいたためフィールド不一致で理由が復号できず、汎用フォールバック文言「Mac側で問題が発生しました」に潰れていた。

## 修正

1. **主修正（macos/DashboardFeature/MessagingService.swift）**: `containsRejectedControlCharacters` で `\n`(LF, 0x0A) を許可。`0x0A < 0x20` のため2箇所の分岐両方で除外。`\r`(CR, submit トリガ)・ESC(0x1B, 端末エスケープ注入)・DEL(0x7F)・その他 C0 制御文字は拒否を維持。
2. **副次修正（ios/PhloxNetworking）**: `ServerErrorDTO` に `error` フィールドを追加し `displayReason = error ?? message ?? reason` を導入。`PhloxAPIClient.mapStatus` の 422/default 両経路を `displayReason` に切替。今後 Mac 側のエラー理由がモバイルに表示される。
3. **観測性（macos/ControlServer）**: 制御サーバの応答が `>= 400` のときだけ `method path bodyLen -> status body(300B truncate)` を error ログ出力（診断計装の一部を恒久化）。リクエストヘッダ（Bearer トークン等）はログしない。

## 検証

- ユニット: macOS `SendMessageTests` 全 pass（新規 `sendMessage_multilineBody_isDeliveredWithNewlinePreserved`＝改行を保ったまま配信を凍結、更新 `sendMessage_controlCharacters_returnsRejected`＝CR/ESC/DEL/汎用C0 の拒否維持）。iOS `PhloxNetworkingTests` 全 pass（新規 `testServer400ErrorFieldSurfacedInMessage`・`testSpawn422ErrorFieldSurfacedAsReason`＝`error` キー経路を凍結）。
- 独立レビュー: `persona-reviewer` pass（MUST/HIGH/MEDIUM 0、根本原因到達・秘密漏洩なし・テスト骨抜きなし）。
- 実機 e2e: 修正入り Debug ビルドで同じ複数行メッセージが正常送信されることをユーザーが確認。
