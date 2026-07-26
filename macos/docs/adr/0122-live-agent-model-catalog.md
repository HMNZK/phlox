---
status: accepted
last-verified: 2026-07-26
supersedes: [0085, 0087]
---

# ADR 0122: live agent model catalog

Claude、Cursor、Codex の spawn 前モデル一覧は、起動時に CLI / app-server から取得して同期スナップショットへ公開する。取得失敗時は内蔵既定値を返し、その状態を観測可能にする。これにより Codex の空カタログという ADR 0085 / 0087 の判断を supersede する。

`/model` が提示する `default`、`opusplan`、`[1m]` 付き alias は除外しない。CLI 自身が選択肢として提示しており、未知値を弾くと新モデルを選べても spawn できない不整合を生むためである。表示名が未取得の ID は ID 自体を表示する。
