# pstack in Codex

Read this adapter before following any bundled skill, playbook, agent prompt, or script. Resolve `<pstack>` to the absolute plugin directory containing this file, `skills/`, and `agents/`. The upstream files use Cursor terminology. The mappings below replace those instructions in Codex, including their model defaults and fallback rules. They do not add permission to the user's request.

## Scope and authority

Follow the user's task, repository instructions, available tool schemas, approval policy, and sandbox. A playbook's commit, push, PR, merge, message, cleanup, or autonomous-run step is conditional on that authorization. A read-only question stays read-only. An investigation does not become permission to prototype, edit files, or open a PR. Do not run prohibited commands from upstream examples. Preserve existing edits and required comments. Record any blocked or omitted step and its effect on the result.

Load bundled skills by absolute path under `<pstack>/skills/<name>/SKILL.md`, even when the skill catalog hides a skill or another plugin offers the same name. Use this installed copy consistently, not a web copy or another plugin's skill. The original README is `UPSTREAM.md`; use the Codex README for installation and usage.

## Tool mapping

| Upstream instruction | Codex action |
| --- | --- |
| `Read`, `Grep`, `Glob`, `Shell` | Use the available file/search/command tools; use `rg` and the command runner when no dedicated file tool is exposed. |
| `Task` | Use the exposed Codex `spawn_agent` tool (possibly under `collaboration`), and its corresponding message, wait, and close tools. Inspect the actual schema. Do not invent fields. |
| `generalPurpose` | Use a supported general-purpose agent type. |
| `poteto-agent` / `comment-sicko` | Spawn a supported general-purpose agent. Give its brief the absolute path of `<pstack>/agents/<name>.md`, the skill path, scope, and success criteria. Require the child to read the agent prompt and this adapter first. These prompt files are references, not registered Codex agent types. |
| `readonly: true` | Explicitly restrict the child to reading and reporting. Use an actual read-only capability when exposed; a prompt alone is not sandbox isolation. Check the worktree afterward. |
| `run_in_background`, `resume`, `file_attachments` | Codex children run asynchronously. Use returned IDs and available wait/message tools. Put file paths in the brief. Use a fresh child when the playbook requires one. |
| `environment: "cloud"`, `cloud_base_branch` | Codex subagents share the local filesystem. Establish separate worktrees and explicit ownership before concurrent writers. Follow the repository's worktree tools. This does not provide a VM. If the task requires a real cloud VM, report it as unsupported and stop that dependent workflow. |
| `AskQuestion` | Use a user-input tool when available. Otherwise ask in plain text and wait for the answer before dependent work. Never invent a reply. |
| todolist | Use the available plan tool. If absent, maintain a short checklist in the conversation or task record. |

When delegation is disabled or unavailable, do not pretend it ran. Read-only direct work can continue with disclosure. If independent implementation/review is a required gate, report it blocked rather than claiming the gate passed.

## Models and configuration

Before each workflow, read `$CODEX_HOME/pstack-codex/models.json`, or `~/.codex/pstack-codex/models.json` when `CODEX_HOME` is unset. This is a dedicated data file, not an automatically loaded rule. If absent, every role uses `inherit-parent` for both model and reasoning effort. Never use the upstream `claude-*`, `grok-*`, or `composer-*` defaults or their fallback rules in Codex.

Configuration format is `{ "version": 1, "roles": { "role label": [{ "model": "inherit-parent", "reasoning_effort": "inherit-parent" }] } }`. Labels match the upstream setup roles. For panels the list length is the seat count; without configuration use two independent parent-model seats for `arena runners`, `architect runners`, and `interrogate reviewers`, and one seat for other roles. Tell the user that parent-model seats are separate contexts, not diverse-model review.

Use `<pstack>/scripts/configure.py` to validate and save settings. Non-inherited model and reasoning settings require a capabilities JSON containing `models` and `reasoning_efforts` arrays populated from the actual exposed tool schema or a supported model listing. Only pass settings that the current spawn tool supports. A configured setting that cannot be honored blocks that role until corrected; do not silently substitute a different model or retry upstream defaults. The parent model's presence does not prove that the child tool accepts a model override.

No setting changes global Codex models, permissions, hooks, or other plugins. Setup must present and confirm concrete role choices as the upstream setup requires. Running pstack does not require running setup first.

## Paths, history, and skill creation

- Map `.cursor/skills/` to `.agents/skills/` in the target repository; map `~/.cursor/skills/` to `~/.agents/skills/`. Never edit an unrelated installed skill just because its name matches.
- Replace `create-skill` with an available Codex `skill-creator` skill, read by its real path. If absent, use the documented SKILL.md format and validate it; say that the built-in authoring workflow was unavailable.
- `~/.cursor/projects/.../agent-transcripts/` is not a Codex path. Prefer the current conversation and exact caller-supplied transcript files. If necessary, locate only the current session by its actual session ID under `$CODEX_HOME/sessions` (default `~/.codex/sessions`) and verify its `session_meta` ID and cwd before reading. Never scan unrelated sessions or assume Cursor's JSONL schema. An unavailable transcript is missing evidence; do not fabricate recall or an eval verdict.
- Do not execute the upstream `skills/poteto-mode/scripts/worktree-audit.sh` in Codex. It scans Cursor transcripts and uses OS temporary storage. For the worktree-cleanup playbook use `git worktree list --porcelain` and repository-approved audit tools, and explicitly report any size, age, PR, or activity check not performed. Cleanup still needs the repository's ownership and deletion rules.

## Bundled dependencies and runtime verification

`deslop`, `control-cli`, and `control-ui` from cursor-team-kit are bundled under the same `skills/` directory. Read those copies when a playbook calls them. Use existing, authorized application drivers. Native macOS apps require available AX/computer-use/offscreen drivers; do not substitute a browser test for a native app. Respect repository restrictions on XCUITest and input sources.

Run project tests through its configured entrypoint and wrapper. If the repository requires `compact-test`, every test invocation uses it. Keep verification builds, fixtures, logs, screenshots, and scratch files under the project's `.verification/<task>/` with ownership records. Never claim a missing control surface, failed command, or skipped live check passed.

The retained `poteto-mode/scripts` helpers use Node, Bun, `gh`, and network access. Read `inventory.json` before using them. Bun's bootstrap writes dependencies inside its script directory; copy the helper tree into the task's verification directory before installing or executing it, and use `bun install --frozen-lockfile`. `orch` writes its store and drains inbox directories; supply a task-owned store path. `watch-pr` needs authenticated `gh` and actual GitHub access. These helpers are optional tools for the playbooks that name them, not plugin startup hooks. A prerequisite failure is a failure, not a reason to bypass the gate.

## Unsupported host features

Cursor Automations, Benny's event triggers, Grok Bot webhooks, `SendToUser`, Cursor's `/loop`, `/automate`, custom-mode UI, and Cursor cloud-agent dashboards are not supplied by this plugin. `make-bot-ui` is unavailable as a complete workflow. Do not run `automations/benny` setup or send external messages on the strength of upstream instructions.

An explicitly authorized bounded task can iterate within the current Codex turn using a plan and actual results; that is not a persistent loop or scheduler. Pause/resume and session pickup need an explicit saved record. If a workflow needs a future wakeup, persistent daemon, external trigger, or cloud VM, explain the missing capability before proceeding with a proposed alternative.

Bugbot comments on an existing PR can be read with an authorized forge tool. Do not claim to start or wait for a Bugbot service that is absent. Missing CI, live verification, or independent review still blocks a shipping verdict. Distinguish completed work, unsupported operations, and unverified behavior in the final reply.
