#!/usr/bin/env python3
"""ios-design.html から各カンプ画面（393×852）の参照 PNG を抽出する。"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "ios-design.html"
OUT = ROOT / "doc/screenshots/reference"

NAMES = [
    ("01-connection-settings", "① 接続設定"),
    ("02-session-list", "② セッション一覧"),
    ("03-session-detail-approval", "③ セッション詳細・承認"),
    ("04-spawn", "④ 新規タスク（spawn）"),
    ("05-delete-confirmation", "⑤ 削除確認（カスケード）"),
    ("06-launch-gate", "⑥ 起動ゲート（Face ID）"),
    ("07-chat-answer", "⑦ 質問への回答（send）"),
    ("08-codex-approval-sheet", "⑧ 承認の応答（Codex 4 択）"),
    ("09-spawn-error", "⑨ spawn 失敗（レート制限）"),
    ("10-unreachable", "⑩ 到達不可（Mac スリープ）"),
    ("11-empty-state", "⑪ 空状態（初回）"),
]


def main() -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright が未インストールです: pip install playwright && playwright install chromium", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    url = HTML.as_uri()

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 2000, "height": 4000})
        page.goto(url, wait_until="load", timeout=120_000)
        page.wait_for_selector("text=① 接続設定", timeout=60_000)
        page.wait_for_timeout(2000)

        for file_stem, label in NAMES:
            header = page.get_by_text(label, exact=True)
            if header.count() == 0:
                print(f"skip {file_stem}: label not found", file=sys.stderr)
                continue
            # ラベル直後の端末ベゼル → 内側 393×812 スクリーン
            bezel = header.locator("xpath=following-sibling::div[1]")
            screen = bezel.locator("xpath=.//div[contains(@style,'393px') and contains(@style,'812px')]")
            target = screen.first if screen.count() > 0 else bezel
            path = OUT / f"{file_stem}.png"
            target.screenshot(path=str(path))
            print(f"saved {path}")

        browser.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
