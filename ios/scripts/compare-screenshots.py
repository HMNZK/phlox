#!/usr/bin/env python3
"""実装スクリーンショットと ios-design.html 参照画像を比較しレポートを生成する。"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACTUAL = ROOT / "doc/screenshots/actual"
REFERENCE = ROOT / "doc/screenshots/reference"
REPORT = ROOT / "doc/screenshots/design-verification.md"

SCREENS = [
    ("01-connection-settings", "① 接続設定", "ConnectionSettingsView"),
    ("02-session-list", "② セッション一覧", "SessionListView"),
    ("03-session-detail-approval", "③ セッション詳細・承認", "SessionDetailView + ApprovalBar"),
    ("04-spawn", "④ 新規タスク（spawn）", "SpawnView"),
    ("05-delete-confirmation", "⑤ 削除確認（カスケード）", "DeleteConfirmationView"),
    ("06-launch-gate", "⑥ 起動ゲート（Face ID）", "LaunchGateView"),
    ("07-chat-answer", "⑦ 質問への回答（send）", "SessionDetailView（⑦専用画面未実装）"),
    ("08-codex-approval-sheet", "⑧ 承認の応答（Codex 4 択）", "CodexApprovalSheet"),
    ("09-spawn-error", "⑨ spawn 失敗（レート制限）", "SpawnView + error banner"),
    ("10-unreachable", "⑩ 到達不可（Mac スリープ）", "UnreachableView"),
    ("11-empty-state", "⑪ 空状態（初回）", "EmptyStateView"),
]

# ピクセル差分率の閾値（Design Parity: 0.92）
MATCH_THRESHOLD = 0.08
# ⑦ はソフトキーボードがシミュレータ依存のため、入力欄より下を比較対象外にする
KEYBOARD_EXCLUDE_STEMS = frozenset({"07-chat-answer"})
KEYBOARD_EXCLUDE_BOTTOM_RATIO = 0.29
# ホームインジケーター帯（実機スクショのみ）
HOME_INDICATOR_EXCLUDE_RATIO = 0.06


def load_image(path: Path):
    from PIL import Image

    img = Image.open(path).convert("RGB")
    return img


def compare_images(actual_path: Path, ref_path: Path, stem: str) -> dict:
    from PIL import Image, ImageChops, ImageStat

    actual = load_image(actual_path)
    ref = load_image(ref_path)

    # 比較用にリサイズ（実機スクショは解像度が異なる）
    size = (393, 852)
    actual_r = actual.resize(size, Image.Resampling.LANCZOS)
    ref_r = ref.resize(size, Image.Resampling.LANCZOS)

    # ステータスバー（時刻・電波）は比較から除外（カンプ 9:41 固定 vs 実機時刻差）
    crop_top = int(size[1] * 0.065)
    crop_bottom = int(size[1] * KEYBOARD_EXCLUDE_BOTTOM_RATIO) if stem in KEYBOARD_EXCLUDE_STEMS else 0
    crop_bottom += int(size[1] * HOME_INDICATOR_EXCLUDE_RATIO)
    crop_box = (0, crop_top, size[0], size[1] - crop_bottom)
    actual_r = actual_r.crop(crop_box)
    ref_r = ref_r.crop(crop_box)

    diff = ImageChops.difference(actual_r, ref_r)
    stat = ImageStat.Stat(diff)
    mean_diff = sum(stat.mean) / 3.0 / 255.0

    return {
        "mean_diff": round(mean_diff, 4),
        "match_score": round(1.0 - mean_diff, 4),
        "pass": mean_diff <= MATCH_THRESHOLD,
        "actual_size": actual.size,
        "ref_size": ref.size,
    }


def visual_notes(name: str) -> list[str]:
    notes: dict[str, list[str]] = {
        "01-connection-settings": [
            "カンプ: 「保存して接続」固定 CTA・セキュリティトグル群あり",
            "実装: フィールドラベル・ボタン文言が簡略化",
        ],
        "02-session-list": [
            "カンプ: 件数・ホスト表示、FAB グラデ、左ピンク帯の強調行",
            "実装: List 標準行・ツールバー spawn アイコン",
        ],
        "03-session-detail-approval": [
            "カンプ: 承認リクエストカード（黄ボーダー）・ターミナル出力折りたたみ",
            "実装: DSApprovalBar（承認/却下）+ モノ出力",
        ],
        "04-spawn": [
            "カンプ: 「新規タスク」・3 エージェントカード・submit トグル",
            "実装: 「新しいセッション」・バッジ選択・ワークスペース欄",
        ],
        "05-delete-confirmation": [
            "カンプ: 中央アラート・暗転・「削除（N 件）」",
            "実装: シート + confirmationDialog 二段",
        ],
        "06-launch-gate": [
            "カンプ: ロゴ・タグライン・Face ID 緑枠アイコン",
            "実装: ロックアイコン + 「Phlox はロックされています」",
        ],
        "07-chat-answer": [
            "カンプ: チャットバブル UI（⑦専用画面）",
            "実装: SessionDetailView の入力バーのみ（⑦未分離）",
        ],
        "08-codex-approval-sheet": [
            "カンプ: 「承認の応答を選択」・4 択アクションシート",
            "実装: 「Codex の承認」・ボタン 4 つ（文言差あり）",
        ],
        "09-spawn-error": [
            "カンプ: カウントダウン・技術詳細行",
            "実装: DSResultBanner の簡略メッセージ",
        ],
        "10-unreachable": [
            "カンプ: 一覧ヘッダー + スケルトン + 下部カード",
            "実装: フルスクリーン UnreachableView",
        ],
        "11-empty-state": [
            "カンプ: 「接続済み」インジケータ・点線アイコン・FAB",
            "実装: 簡略コピー「セッションはありません」",
        ],
    }
    return notes.get(name, [])


def main() -> int:
    results = []
    for file_stem, label, view in SCREENS:
        actual = ACTUAL / f"{file_stem}.png"
        ref = REFERENCE / f"{file_stem}.png"
        entry = {
            "file": file_stem,
            "label": label,
            "view": view,
            "actual_exists": actual.exists(),
            "ref_exists": ref.exists(),
            "notes": visual_notes(file_stem),
        }
        if actual.exists() and ref.exists():
            try:
                entry.update(compare_images(actual, ref, file_stem))
            except Exception as e:
                entry["error"] = str(e)
                entry["pass"] = False
        else:
            entry["pass"] = False
            if not actual.exists():
                entry["error"] = "actual なし"
            if not ref.exists():
                entry["error"] = (entry.get("error", "") + " reference なし").strip()
        results.append(entry)

    lines = [
        "# デザイン検証レポート（ios-design.html vs 実装）",
        "",
        f"- **日付**: {date.today().isoformat()}",
        f"- **参照**: `ios-design.html` → `doc/screenshots/reference/`",
        f"- **実装**: XCUITest → `doc/screenshots/actual/`",
        f"- **比較閾値**: 平均ピクセル差 ≤ {MATCH_THRESHOLD:.0%} を pass（構造的一致の目安）",
        f"- **⑦ 特例**: ソフトキーボードはシミュレータ依存のため、下部 {KEYBOARD_EXCLUDE_BOTTOM_RATIO:.0%} を比較対象外",
        "",
        "## サマリー",
        "",
    ]

    passed = sum(1 for r in results if r.get("pass"))
    lines.append(f"| 項目 | 値 |")
    lines.append(f"|------|-----|")
    lines.append(f"| 画面数 | {len(results)} |")
    lines.append(f"| 自動比較 pass | **{passed}/{len(results)}** |")
    lines.append("")
    lines.append("## 画面別結果")
    lines.append("")
    lines.append("| カンプ | View | 比較 | match | 備考 |")
    lines.append("|--------|------|------|-------|------|")

    for r in results:
        status = "✅ pass" if r.get("pass") else "❌ gap"
        score = r.get("match_score", "—")
        note = "; ".join(r["notes"][:2]) if r["notes"] else (r.get("error") or "")
        lines.append(f"| {r['label']} | `{r['view']}` | {status} | {score} | {note} |")

    lines.extend([
        "",
        "## 画像",
        "",
        "各画面の並列比較:",
        "",
    ])
    for file_stem, label, _ in SCREENS:
        lines.append(f"### {label}")
        lines.append("")
        lines.append(f"| カンプ | 実装 |")
        lines.append(f"|--------|------|")
        lines.append(f"| ![ref](reference/{file_stem}.png) | ![actual](actual/{file_stem}.png) |")
        lines.append("")

    lines.append("## 総合判定")
    lines.append("")
    if passed == len(results):
        lines.append("全画面が閾値内で一致（ピクセルベース）。")
    else:
        lines.append(
            "MVP 実装はカンプの**情報設計・フロー**は概ね一致するが、"
            "**ビジュアル詳細（レイアウト・コピー・装飾）にギャップ**がある。"
            "特に ②一覧・⑥ゲート・⑦チャット・⑩到達不可はカンプとの差が大きい。"
        )

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    (REPORT.parent / "comparison-results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote {REPORT}")
    print(f"pass {passed}/{len(results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
