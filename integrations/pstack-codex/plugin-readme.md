# pstack for Codex

This independent adaptation packages pstack workflows for Codex, including Phlox's Codex sessions. It preserves upstream reference files and scripts and adds a Codex adapter. It is not an official Cursor or OpenAI release.

Read [the Codex adapter](codex.md) for tools, delegation, dedicated settings, transcript privacy, runtime requirements, and unsupported host features. [source.json](source.json) records the exact upstream revision and content hash. [inventory.json](inventory.json) classifies the packaged upstream files. [UPSTREAM.md](UPSTREAM.md) is the unmodified upstream introduction; its Cursor installation instructions and model defaults do not apply here.

## Use

Select this plugin's `poteto-mode` skill in a new Codex session and describe the task and its acceptance criteria. In a terminal, explicitly invoke `$pstack-codex:poteto-mode`. In Phlox type `/pstack-codex:poteto-mode`, select the candidate, then append the task and send. Selection attaches the native skill input; merely typing a slash command does not prove the skill was attached.

Setup is optional. Without it, child agents inherit the parent model and reasoning settings. Select `setup-pstack` to configure validated role assignments in the dedicated Codex home data file. This does not change Codex's global model or permissions. When review seats share a model, they provide separate contexts, not diverse-model review.

`deslop`, `control-cli`, and `control-ui` are included from cursor-team-kit. Native app checks need an available native driver; missing drivers are reported as unverified. The original Bun/Node/GitHub helper scripts are not startup hooks. Prepare and test them in your project's verification directory before use.

Cursor Automations, Benny triggers, Grok Bot webhooks, Cursor cloud VMs, and persistent `/loop` scheduling are unsupported. A workflow that depends on one cannot receive a complete verdict. User authorization and repository rules govern commits, PRs, merges, messages, and cleanup.

## Attribution

Upstream pstack is by Lauren Tan, under [its MIT license](LICENSE). The bundled cursor-team-kit skills are by Eric Zakariasson and contributors under [their MIT license](LICENSE-cursor-team-kit). Codex adapter and generator changes are maintained with Phlox. Preserve both notices when redistributing.
