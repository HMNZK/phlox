#!/usr/bin/env python3
"""Run pstack in an isolated Codex home against a disposable clamp fixture."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def snapshot(fixture):
    return {str(p.relative_to(fixture)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in fixture.rglob("*.py")}


def verify_delegation(home, events, fixture, minimum):
    parent = next(event["thread_id"] for event in events if event.get("type") == "thread.started")
    completed = []
    for path in (home / "sessions").rglob("*.jsonl"):
        with path.open() as stream:
            first = json.loads(stream.readline())
            meta = first.get("payload", {})
            source = meta.get("source", {})
            spawn = source.get("subagent", {}).get("thread_spawn", {}) if isinstance(source, dict) else {}
            if spawn.get("parent_thread_id") != parent or meta.get("cwd") != str(fixture):
                continue
            if any(json.loads(line).get("payload", {}).get("type") == "task_complete" for line in stream):
                completed.append(meta["id"])
    if len(completed) < minimum:
        raise ValueError(f"Expected {minimum} completed direct children, observed {len(completed)}")
    return completed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", choices=("fix", "review"))
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--plugin", type=Path, required=True)
    parser.add_argument("--record", type=Path, required=True)
    parser.add_argument("--model", help="An available model; otherwise use the Codex default")
    args = parser.parse_args()
    fixture, plugin, record = args.fixture.resolve(), args.plugin.resolve(), args.record.resolve()
    if ".verification" not in fixture.parts or ".verification" not in Path(os.environ["CODEX_HOME"]).parts:
        raise ValueError("Use a disposable fixture and isolated CODEX_HOME under .verification")
    before = snapshot(fixture)
    if "clamp.py" not in before or not (fixture / "tests/test_clamp.py").is_file():
        raise ValueError("Expected the task-owned clamp verification fixture")
    record.mkdir(parents=True, exist_ok=True)
    temporary = fixture / ".verification/tmp"
    temporary.mkdir(parents=True, exist_ok=True)
    skill = "poteto-mode" if args.scenario == "fix" else "interrogate"
    task = (
        "Fix the clamp.py defect: clamp(5,2,8) must return 5 and clamp(12,2,8) must return 8. "
        "Reproduce first, delegate the fix per the skill, and run the existing tests without changing tests. "
        "The public API and reversed-bound error stay the same. "
        if args.scenario == "fix" else
        "Review clamp.py and tests/test_clamp.py against the closed-interval contract. "
        "Use two independent reviewer subagents with inherited models, disclose that the same model is used, "
        "and synthesize their actual findings. Do not edit source or tests; only test temporary files under TMPDIR are writable. "
    )
    prompt = (
        f"Read {plugin}/codex.md, then use ${skill} at {plugin}/skills/{skill}/SKILL.md. "
        + task + "Scope is this disposable fixture only. No commits, PRs, pushes, or outside edits. "
        "Run tests through ~/.agents/scripts/compact-test pstack-fixture python3 -m unittest discover -s tests -v. "
        "Keep delegation as small as the workflow allows. Answer in Japanese."
    )
    with (record / "events.jsonl").open("w") as out, (record / "stderr.log").open("w") as err:
        process = subprocess.Popen(
            ["codex", "exec", *(["-m", args.model] if args.model else []),
             "--sandbox", "workspace-write",
             "--json", "-o", str(record / "answer.md"), prompt],
            stdin=subprocess.DEVNULL, stdout=out, stderr=err, cwd=fixture,
            env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1", TMPDIR=str(temporary)),
        )
        process_record = {"pid": process.pid, "executable": "codex exec", "scenario": args.scenario}
        (record / "process.json").write_text(json.dumps(process_record))
        try:
            code = process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=15)
            raise
        finally:
            process_record.update(stopped=process.poll() is not None, exit_code=process.poll())
            (record / "process.json").write_text(json.dumps(process_record))
    if code:
        raise RuntimeError(f"Codex failed, exit={code}; see {record}")
    events = [json.loads(line) for line in (record / "events.jsonl").read_text().splitlines()]
    if not any(event.get("type") == "turn.completed" for event in events):
        raise ValueError("Codex did not complete a turn")
    if any(event.get("type") in ("error", "turn.failed") for event in events):
        raise ValueError("Codex reported a failed turn")
    if "ERROR" in (record / "stderr.log").read_text():
        raise ValueError("Codex reported an execution error; inspect stderr.log")
    children = verify_delegation(Path(os.environ["CODEX_HOME"]), events, fixture, 1 if args.scenario == "fix" else 2)
    (record / "children.json").write_text(json.dumps(children))
    after = snapshot(fixture)
    if args.scenario == "review" and before != after:
        raise ValueError("Read-only review changed Python source")
    if args.scenario == "fix" and {k: v for k, v in before.items() if k != "clamp.py"} != {k: v for k, v in after.items() if k != "clamp.py"}:
        raise ValueError("Fix changed test or unrelated source")
    wrapper = Path.home() / ".agents/scripts/compact-test"
    subprocess.run([str(wrapper), "pstack-fixture-after", "python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                   cwd=fixture, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"), check=True)
    print(f"PASS: {args.scenario}; actual transcript and answer saved under {record}")


if __name__ == "__main__":
    main()
