#!/usr/bin/env python3
"""Build a reproducible local marketplace from the pinned pstack source."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote


HERE = Path(__file__).resolve().parent
DEPENDENCIES = ("deslop", "control-cli", "control-ui")
PATTERNS = {
    "delegation": r"\bTask\b|subagent_type|run_in_background|cloud_base_branch",
    "models": r"grok-\d|claude-\w+-\d|composer-|pstack-models",
    "history": r"agent-transcripts|\.cursor/projects",
    "skill-authoring": r"create-skill",
    "control": r"control-cli|control-ui|/deslop",
    "host-only": r"SendToUser|api2\.cursor|Cursor [Aa]utomation|/loop|/automate\b|[Cc]loud [Aa]gent",
    "runtime": r"\bBun\b|bun |\bgh |node_modules|rmSync|unlinkSync",
}


def json_bytes(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def source_files(source):
    roots = [source / "pstack", source / "cursor-team-kit/LICENSE"]
    roots.extend(source / "cursor-team-kit/skills" / name for name in DEPENDENCIES)
    result = {}
    for root in roots:
        if not root.exists():
            raise ValueError(f"Missing upstream component: {root}")
        for path in sorted(root.rglob("*") if root.is_dir() else [root]):
            if path.is_symlink():
                raise ValueError(f"Upstream symlink is not supported: {path}")
            if path.is_file():
                if path.name.startswith(".env"):
                    raise ValueError(f"Environment files are not packaged: {path}")
                result[path.relative_to(source).as_posix()] = (
                    path.read_bytes(), bool(path.stat().st_mode & 0o111)
                )
    return result


def digest(files):
    value = hashlib.sha256()
    for name, (data, executable) in sorted(files.items()):
        value.update(json_bytes([name, executable, hashlib.sha256(data).hexdigest()]))
    return value.hexdigest()


def verify_source(source, lock):
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if revision != lock["revision"]:
        raise ValueError(f"Upstream revision differs: {revision}")
    files = source_files(source)
    if digest(files) != lock["sha256"]:
        raise ValueError("Upstream contents differ from source.json; review the update before changing the lock")
    manifest = json.loads(files["pstack/plugin.json"][0])
    if manifest["version"] != lock["upstream_version"]:
        raise ValueError("Upstream version differs")
    return files


def acquire(source, lock):
    if source.exists():
        return
    source.parent.mkdir(parents=True, exist_ok=True)
    for args in (
        ["git", "init", str(source)],
        ["git", "-C", str(source), "remote", "add", "origin", lock["repository"]],
        ["git", "-C", str(source), "sparse-checkout", "set", "pstack", "cursor-team-kit"],
        ["git", "-C", str(source), "fetch", "--depth", "1", "origin", lock["revision"]],
        ["git", "-C", str(source), "checkout", "--detach", "FETCH_HEAD"],
    ):
        subprocess.run(args, check=True)


def convert_skill(data, path):
    text = data.decode()
    match = re.match(r"\A---\n(.*?)\n---\n(.*)\Z", text, re.S)
    if not match:
        raise ValueError(f"Invalid skill frontmatter: {path}")
    frontmatter, body = match.groups()
    name = re.search(r"^name: ([a-z0-9-]+)$", frontmatter, re.M)
    description = re.search(r"^description: [^\n]+(?:\n[ \t]+[^\n]*)*", frontmatter, re.M)
    if not name or not description or name[1] != Path(path).parent.name:
        raise ValueError(f"Invalid skill identity or description: {path}")
    note = "Read [the Codex adapter](../../codex.md) before following this skill. Its mappings replace Cursor-specific defaults and operations.\n\n"
    if name[1] == "make-bot-ui":
        note += "This workflow requires Grok Bot and Cursor Automations and is unsupported in Codex. Explain that limitation and stop; the upstream instructions below are reference material only.\n\n"
    converted = f"---\nname: {name[1]}\n{description[0]}\n---\n\n{note}{body.lstrip()}"
    explicit = bool(re.search(r"^disable-model-invocation: true$", frontmatter, re.M))
    return converted.encode(), explicit


def markdown_destinations(text):
    for match in re.finditer(r"\]\(", text):
        start = match.end()
        if text[start:start + 1] == "<":
            end = text.find(">", start + 1)
            if end >= 0:
                yield text[start + 1:end]
            continue
        cursor, depth = start, 0
        while cursor < len(text):
            char = text[cursor]
            if char == "\\":
                cursor += 2
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            cursor += 1
        yield re.sub(r"\\([() ])", r"\1", text[start:cursor])
    for match in re.finditer(r"^ {0,3}\[(?!\^)[^\]\n]+\]:[ \t]*(<[^>\n]+>|\S+)", text, re.M):
        yield match[1].removeprefix("<").removesuffix(">")


def validate_links(files):
    for name, (data, _) in files.items():
        if not name.endswith(".md"):
            continue
        for href in markdown_destinations(data.decode()):
            target = unquote(href.split("#", 1)[0])
            if not target or target == "url" or re.match(r"[a-z][a-z0-9+.-]*:", target):
                continue
            parts = []
            for part in (Path(name).parent / target).parts:
                if part == "..":
                    if not parts:
                        raise ValueError(f"Link escapes plugin: {name}: {href}")
                    parts.pop()
                elif part != ".":
                    parts.append(part)
            resolved = "/".join(parts)
            if resolved not in files and not any(p.startswith(resolved + "/") for p in files):
                raise ValueError(f"Missing reference: {name}: {href}")


def render(upstream, lock):
    files = {}
    inventory = []
    for name, (data, executable) in sorted(upstream.items()):
        if name.startswith("pstack/"):
            dest = name.removeprefix("pstack/")
            if dest.startswith(".cursor-plugin/") or dest == ".gitignore":
                continue
            if dest == "README.md":
                dest = "UPSTREAM.md"
        elif name == "cursor-team-kit/LICENSE":
            dest = "LICENSE-cursor-team-kit"
        else:
            dest = name.removeprefix("cursor-team-kit/")
        text = data.decode() if name.endswith((".md", ".sh", ".ts", ".mjs")) else ""
        categories = [key for key, pattern in PATTERNS.items() if re.search(pattern, text)]
        inventory.append({"source": name, "path": dest, "sha256": hashlib.sha256(data).hexdigest(),
                          "categories": categories, "executable": executable})
        if re.fullmatch(r"skills/[^/]+/SKILL.md", dest):
            data, explicit = convert_skill(data, dest)
            if len(data) > 8_000:
                header, body = data.decode().split("\n---\n", 1)
                workflow = str(Path(dest).parent / "workflow.md")
                if workflow in files or "pstack/" + workflow in upstream or "cursor-team-kit/" + workflow in upstream:
                    raise ValueError(f"Workflow path already exists: {workflow}")
                files[workflow] = (body.encode(), False)
                data = (header + "\n---\n\nRead [the Codex adapter](../../codex.md) first. "
                        "Then read [the complete workflow](workflow.md) before doing any work. "
                        "Follow the complete workflow with the adapter's tool and permission mappings.\n").encode()
            if explicit:
                policy = str(Path(dest).parent / "agents/openai.yaml")
                files[policy] = (b"policy:\n  allow_implicit_invocation: false\n", False)
        elif re.fullmatch(r"agents/[^/]+\.md", dest):
            text = data.decode()
            end = text.find("\n---", 4)
            if end < 0:
                raise ValueError(f"Invalid agent frontmatter: {name}")
            data = (text[:end + 4] + "\n\nRead [the Codex adapter](../codex.md) first. Use the exact poteto-mode path supplied by the parent; do not search Cursor installations.\n" + text[end + 4:]).encode()
        files[dest] = (data, executable)
    for name in ("codex.md", "configure.py"):
        dest = name if name.endswith(".md") else "scripts/" + name
        files[dest] = ((HERE / name).read_bytes(), name.endswith(".py"))
    files["skills/setup-pstack/SKILL.md"] = ((HERE / "setup-pstack.md").read_bytes(), False)
    interface = {"displayName": "pstack for Codex", "shortDescription": "pstack workflows adapted for Codex and Phlox"}
    manifest = {"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
                "name": "pstack-codex", "version": lock["adapter_version"],
                "description": "Independent Codex adaptation of pstack, with bundled cursor-team-kit control and cleanup skills. Cursor-only host services are unsupported.",
                "author": {"name": "Phlox contributors"}, "license": "MIT",
                "extensions": {"com.openai": {"interface": interface}}}
    files["plugin.json"] = (json_bytes(manifest), False)
    compatibility = {key: value for key, value in manifest.items() if key not in ("$schema", "extensions")}
    compatibility.update(skills="./skills/", interface=interface)
    files[".codex-plugin/plugin.json"] = (json_bytes(compatibility), False)
    files["source.json"] = (json_bytes(lock), False)
    files["inventory.json"] = (json_bytes(inventory), False)
    files["README.md"] = ((HERE / "plugin-readme.md").read_bytes(), False)
    validate_links(files)
    marketplace = {"name": "phlox-pstack", "interface": {"displayName": "Phlox pstack"},
                   "plugins": [{"name": "pstack-codex", "source": {"source": "local", "path": "./plugins/pstack-codex"},
                                "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Developer Tools"}]}
    result = {"plugins/pstack-codex/" + path: value for path, value in files.items()}
    result[".agents/plugins/marketplace.json"] = (json_bytes(marketplace), False)
    return result


def publish(files, output, check=False):
    if output.is_symlink():
        raise ValueError("Output must not be a symlink")
    if output.exists():
        existing = {}
        for path in output.rglob("*"):
            if path.is_symlink():
                raise ValueError(f"Output contains symlink: {path}")
            if path.is_file():
                existing[path.relative_to(output).as_posix()] = (path.read_bytes(), bool(path.stat().st_mode & 0o111))
        if existing == files:
            return
        if check or existing:
            raise ValueError("Output differs; existing files were not changed. Build into a new directory")
    elif check:
        raise ValueError("Output is missing")
    output.mkdir(parents=True, exist_ok=True)
    for name, (data, executable) in files.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o755 if executable else 0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=HERE.parents[1] / ".verification/pstack-codex/upstream")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    lock = json.loads((HERE / "source.json").read_text())
    try:
        acquire(args.source, lock)
        upstream = verify_source(args.source, lock)
        files = render(upstream, lock)
        publish(files, args.output, args.check)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"pstack build: {error}\n")
    count = sum(bool(re.fullmatch(r"plugins/pstack-codex/skills/[^/]+/SKILL.md", name)) for name in files)
    print(f"pstack-codex {lock['adapter_version']}: {count} skills; {args.output.resolve()}")


if __name__ == "__main__":
    main()
