#!/usr/bin/env python3
"""Phlox の Control API を最小限だけ真似るローカル偽サーバー（調査用）。

なぜ要るか: `-UITesting` のデモは一覧の状態を固定して配信を止めるため、
「実データが動いている状態」でしか出ない不具合（大タイトルの消失など）を再現できない。
本スクリプトは Mac の Phlox 本体に触らずに、その「動いている状態」だけを作る。

使い方:
    python3 ios/scripts/fake-phlox-server.py --port 53099 --churn

    --churn  ポーリングのたびにセッションの件数・状態を変え、たまに 500 を返して
             オフライン復帰を起こす（状態遷移を意図的に多発させるモード）
"""
import argparse
import json
import random
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

STATE = {"tick": 0, "churn": False}
LOCK = threading.Lock()

KINDS = ["claudeCode", "codex", "cursor"]
STATUSES = ["running", "awaitingApproval", "idle", "completed", "starting"]
NAMES = ["Rose", "Tulip", "Poppy", "Iris", "Lily", "Aster", "Zinnia"]


def sessions_payload(tick):
    if not STATE["churn"]:
        return [
            {"id": "s-1", "name": "Rose", "kind": "claudeCode", "status": "awaitingApproval",
             "workspace": "~/Projects/app", "projectId": "p-1", "projectName": "app"},
            {"id": "s-2", "name": "Tulip", "kind": "codex", "status": "running",
             "workspace": "~/Projects/app", "projectId": "p-1", "projectName": "app"},
        ]
    rng = random.Random(tick)
    count = 1 + (tick % 4)
    out = []
    for i in range(count):
        out.append({
            "id": f"s-{i + 1}",
            "name": NAMES[(tick + i) % len(NAMES)],
            "kind": KINDS[(tick + i) % len(KINDS)],
            "status": STATUSES[(tick * 3 + i) % len(STATUSES)],
            "workspace": "~/Projects/app",
            "projectId": f"p-{1 + (i % 2)}",
            "projectName": ["app", "infra"][i % 2],
        })
    rng.shuffle(out)
    return out


def approvals_payload(tick):
    if tick % 3 == 0:
        return []
    return [{"id": "a-1", "sessionID": "s-1", "kind": "claudeCode",
             "prompt": "ControlServer.swift を削除して続行しますか？"}]


# 実機の Mac 端末は 138 桁だった（2026-07-27 実測）。モバイル側の折り返しを現実的な幅で確かめるため、
# Claude Code の TUI を模した 138 桁のスクリーンを返す。
ANSI_COLS = 138
E = "\x1b"
ANSI_SCREEN = "\n".join([
    f"{E}[38;5;208m ▐▛███▜▌{E}[0m   {E}[1mClaude Code{E}[0m {E}[2mv2.1.220{E}[0m",
    f"{E}[38;5;208m▝▜█████▛▘{E}[0m  {E}[2mHaiku 4.5 · Claude Max{E}[0m",
    f"{E}[38;5;208m  ▘▘ ▝▝  {E}[0m  {E}[2m~/Projects/Phlox-oss{E}[0m",
    "",
    f"{E}[32m❯{E}[0m /model",
    f"  {E}[2m⎿{E}[0m  {E}[33mKept model as Haiku 4.5{E}[0m",
    "",
    f"{E}[32m❯{E}[0m hello",
    "",
    f"{E}[38;5;39m⏺{E}[0m こんにちは。何かお手伝いできることはありますか？"
    "現在のブランチで作業中の内容について、具体的なタスクがあれば教えてください。",
    "",
    f"{E}[38;5;213m✳{E}[0m {E}[2mCooked for 8s{E}[0m",
    f"{E}[2m" + "─" * ANSI_COLS + f"{E}[0m",
    f"{E}[32m❯{E}[0m ",
    f"{E}[2m" + "─" * ANSI_COLS + f"{E}[0m",
    f"  {E}[36m~/Projects/Phlox-oss{E}[0m {E}[2m│{E}[0m {E}[35mfeature/session-view-ux{E}[0m {E}[2m│{E}[0m "
    f"{E}[33mHaiku 4.5{E}[0m {E}[2m│{E}[0m ctx 72% {E}[2m│{E}[0m 5h 31% (36m) {E}[2m│{E}[0m "
    f"7d 47% (7/28 13:00) {E}[2m│{E}[0m {E}[32m$0.11{E}[0m",
    f"  {E}[2m▸▸ bypass permissions on (shift+tab to cycle) · install gh for PR support{E}[0m",
])


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 既定のアクセスログは黙らせる
        pass

    def _send(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.strip("/")
        query = parse_qs(parsed.query)

        with LOCK:
            STATE["tick"] += 1
            tick = STATE["tick"]

        # churn 中はたまに落として、オフライン → 復帰の遷移を起こす
        if STATE["churn"] and tick % 11 == 0:
            self._send(500, {"error": "injected failure"})
            return

        parts = path.split("/")
        if path == "sessions":
            self._send(200, {"sessions": sessions_payload(tick)})
        elif path == "approvals":
            self._send(200, {"approvals": approvals_payload(tick)})
        elif path == "usage":
            self._send(200, {"agents": []})
        elif len(parts) == 3 and parts[0] == "sessions" and parts[2] == "output":
            if query.get("format", [""])[0] == "ansi":
                self._send(200, {"text": ANSI_SCREEN, "format": "ansi", "cols": ANSI_COLS})
            else:
                self._send(200, {"text": "> running tests...\nOK"})
        elif len(parts) == 3 and parts[0] == "sessions" and parts[2] == "messages":
            self._send(200, {"messages": [], "cursor": "c-1", "snapshot": True})
        elif len(parts) == 3 and parts[0] == "sessions" and parts[2] == "ready":
            self._send(200, {"ready": True})
        elif len(parts) == 3 and parts[0] == "sessions" and parts[2] == "subagents":
            self._send(200, {"subagents": []})
        elif len(parts) == 3 and parts[0] == "sessions" and parts[2] == "usage":
            self._send(200, {})
        elif len(parts) == 3 and parts[0] == "agents" and parts[2] == "models":
            self._send(200, {"models": [], "defaultModel": None})
        else:
            self._send(404, {"error": f"unknown path: {path}"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        self._send(200, {"ok": True})

    do_PATCH = do_POST
    do_DELETE = do_POST


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=53099)
    ap.add_argument("--churn", action="store_true")
    args = ap.parse_args()
    STATE["churn"] = args.churn
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"fake phlox server on http://127.0.0.1:{args.port} churn={args.churn}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
