---
status: active
last-verified: 2026-07-11
---

# QR ペアリング契約 v1（Mac ↔ Phlox-mobile シーム契約）

> **このファイルの役割**: モバイルペアリング用 QR コードのペイロード形式と両側の実装要件を凍結する（ADR [0076](../adr/0076-adopt-qr-pairing-for-mobile.md) の実装契約）。**この契約は凍結済み。変更には両リポジトリの合意（Phlox 側はゲート②承認）が必要。**
> **書かないもの**: APNs 連携（→ [apns-companion-contract.md](apns-companion-contract.md)）、採用理由（→ ADR 0076）。

## 契約: QR ペイロード形式（v1）

QR コードに符号化する文字列は次の URL 1本とする:

```
phlox://pair?v=1&host=<HOST>&port=<PORT>&token=<TOKEN>&name=<NAME>
```

| パラメータ | 必須 | 形式 | 意味 |
|---|---|---|---|
| `v` | 必須 | 固定値 `1` | 契約バージョン。iOS 側は `1` 以外を拒否しエラー表示する |
| `host` | 必須 | Tailscale IPv4（dotted quad、例 `100.64.12.34`） | MobileProxy の待受アドレス。**スキャン時点の値**であり、Tailscale IP が変わったら再ペアリング（QR は Mac 側で都度生成・キャッシュしない） |
| `port` | 必須 | 10 進整数（1–65535） | MobileProxy の待受ポート |
| `token` | 必須 | 64 文字の16進小文字 `[0-9a-f]{64}` | モバイルトークン（[apns-companion-contract.md](apns-companion-contract.md) と同一のもの。Bearer 認証に使う） |
| `name` | 任意 | percent-encoded UTF-8 | 接続先 Mac の表示名（iOS 側の接続一覧表示用） |

- パラメータ順序は上表のとおり固定（`v` → `host` → `port` → `token` → `name`）。iOS 側は順序に依存せずパースしてよいが、Mac 側は固定順で生成する。
- `token` 以外に機密は載せない。`token` は Mac 遠隔操作の全権（ADR 0074 決定1）であるため、**QR の表示は Mac 側で明示操作＋60秒自動非表示**とする。
- Tailscale 未検出（loopback 限定動作）時は接続不能のため、Mac 側は QR を生成しない（生成 API は失敗を型で返す）。

## Mac 側（本リポジトリ）の実装要件

1. ペイロード生成: `Packages/MobileProxy` の `PairingPayload`（host/port/token/name → 上記 URL 文字列。検証付き・ユニットテストで固定）。
2. QR 表示: 設定画面のモバイル接続セクション（`isCompanionClientBundled` ゲート配下 = iOS アプリ同梱まで非表示）。CoreImage `CIFilter.qrCodeGenerator` で描画。明示操作で表示・60秒で自動非表示・トークン再発行時は即時更新。

## iOS 側（Phlox-mobile）への実装依頼

1. カメラ / PhotosPicker で QR を読み取り、上記 URL をパースする（`v=1` 以外・`token` 形式不正・`host`/`port` 欠落は明確なエラー表示）。
2. パース結果（host・port・token・name）を Keychain に保存し、既存の HTTP 接続設定（Bearer 認証）へ反映する。
3. 接続失敗（Tailscale IP 変更等）時は「Mac 側で QR を再表示して再スキャン」を案内する。
4. `phlox://` カスタム URL スキームを登録する場合、カメラアプリからの起動経由でも同じパース処理に合流させる。

## 参照

- 採用決定: [ADR 0076](../adr/0076-adopt-qr-pairing-for-mobile.md) / 脅威モデル: [ADR 0074](../adr/0074-mobile-remote-control-design.md) 決定1
- トークン・API 契約: [apns-companion-contract.md](apns-companion-contract.md)
- 現行構成: [architecture/mobile-proxy.md](../architecture/mobile-proxy.md)
