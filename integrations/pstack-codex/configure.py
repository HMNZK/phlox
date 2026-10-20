#!/usr/bin/env python3
"""Validate dedicated pstack role settings without changing Codex configuration."""

import argparse
import json
import os
from pathlib import Path
import tempfile


ROLES = (
    "feature, refactoring", "bug-fix", "perf-issue", "hillclimb",
    "judgment and prose", "hardest tasks", "how explorer", "how explainer",
    "why investigators", "why synthesizer", "reflect tooling",
    "reflect judgment, divergent, synthesizer", "arena runners",
    "arena cross-judge pool", "swarm workers", "architect runners",
    "interrogate reviewers",
)
PANELS = {"arena runners", "architect runners", "interrogate reviewers"}


def defaults():
    return {"version": 1, "roles": {
        role: [{"model": "inherit-parent", "reasoning_effort": "inherit-parent"}
               for _ in range(2 if role in PANELS else 1)]
        for role in ROLES
    }}


def validate(config, capabilities):
    if not isinstance(config, dict) or set(config) != {"version", "roles"} or type(config["version"]) is not int or config["version"] != 1:
        raise ValueError("Expected version 1 and roles")
    if not isinstance(config["roles"], dict) or set(config["roles"]) - set(ROLES):
        raise ValueError("Unknown role or invalid roles object")
    if not isinstance(capabilities, dict):
        raise ValueError("Capabilities must be an object")
    for key in ("models", "reasoning_efforts"):
        values = capabilities.get(key, [])
        if not isinstance(values, list) or any(not isinstance(v, str) or not v for v in values):
            raise ValueError(f"Invalid capability list: {key}")
    for role, seats in config["roles"].items():
        if not isinstance(seats, list) or not seats:
            raise ValueError(f"Empty or invalid seat list: {role}")
        if role not in PANELS and role != "arena cross-judge pool" and len(seats) != 1:
            raise ValueError(f"Scalar role needs one seat: {role}")
        for seat in seats:
            if not isinstance(seat, dict) or set(seat) != {"model", "reasoning_effort"}:
                raise ValueError(f"Invalid seat: {role}")
            for field, capability in (("model", "models"), ("reasoning_effort", "reasoning_efforts")):
                value = seat[field]
                if not isinstance(value, str) or (value != "inherit-parent" and value not in capabilities.get(capability, [])):
                    raise ValueError(f"Unavailable {field}: {value!r} ({role})")
    return config


def save(path, config, capabilities):
    validate(config, capabilities)
    path = Path(path)
    if path.is_symlink():
        raise ValueError("Refusing to replace a symlink")
    if path.name.startswith(".env"):
        raise ValueError("Refusing an environment file")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(config, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="Proposed role configuration; defaults to inheritance")
    parser.add_argument("--capabilities", type=Path, help="Observed supported child model/effort values")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = json.loads(args.input.read_text()) if args.input else defaults()
        capabilities = json.loads(args.capabilities.read_text()) if args.capabilities else {}
        save(args.output, config, capabilities)
    except (OSError, ValueError) as error:
        parser.exit(1, f"pstack configuration: {error}\n")
    print(args.output.resolve())


if __name__ == "__main__":
    main()
